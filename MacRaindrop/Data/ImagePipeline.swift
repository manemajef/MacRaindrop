import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Loads cover images as small, already-decoded thumbnails, and keeps them.
///
/// Covers are usually full-size page images, far larger than a card. Each one is downloaded
/// once, downsampled off the main thread to `maxPixelSize`, and kept twice: decoded in memory
/// (`cachedImage(for:)` answers synchronously, so a card scrolled back into view shows its cover
/// at once) and as a small file in Caches (so the next launch doesn't download it again).
///
/// The thumbnail size doesn't depend on how wide a card is, so resizing never reloads anything.
nonisolated final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    /// The longest side of a thumbnail, in pixels: a wide card on a Retina display.
    static let maxPixelSize = 720

    private struct Load {
        let task: Task<CGImage?, Never>
        /// Views still waiting for it. When the last one goes away, the download is cancelled.
        var waiters: Int
    }

    private let memory = NSCache<NSURL, CGImage>()
    private let loads = Mutex<[URL: Load]>([:])
    /// Covers that didn't load this session (gone, not an image), so scrolling past doesn't retry them.
    private let failures = Mutex<Set<URL>>([])
    private let session: URLSession
    private let directory: URL

    private init() {
        // Decoded thumbnails are about 2 MB each. This keeps a few hundred.
        memory.totalCostLimit = 400 * 1024 * 1024

        // The originals are never needed again once downsampled, so they aren't cached.
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)

        directory = URL.cachesDirectory.appending(path: "Covers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The thumbnail, if it's already in memory. Cheap enough to call from a view's body.
    func cachedImage(for url: URL) -> CGImage? {
        memory.object(forKey: url as NSURL)
    }

    /// The thumbnail, from memory, disk or the network. Nil when the cover can't be loaded.
    func image(for url: URL) async -> CGImage? {
        if let image = cachedImage(for: url) { return image }
        if failures.withLock({ $0.contains(url) }) { return nil }

        let task = loads.withLock { loads in
            if var load = loads[url] {
                load.waiters += 1
                loads[url] = load
                return load.task
            }
            let task = Task.detached(priority: .userInitiated) { await self.load(url) }
            loads[url] = Load(task: task, waiters: 1)
            return task
        }

        return await withTaskCancellationHandler {
            let image = await task.value
            loads.withLock { loads in
                if loads[url]?.task == task { loads[url] = nil }
            }
            return image
        } onCancel: {
            loads.withLock { loads in
                guard var load = loads[url], load.task == task else { return }
                load.waiters -= 1
                if load.waiters == 0 {
                    load.task.cancel()
                    loads[url] = nil
                } else {
                    loads[url] = load
                }
            }
        }
    }

    // MARK: Loading

    private func load(_ url: URL) async -> CGImage? {
        let file = fileURL(for: url)
        if let image = Self.decode(contentsOf: file) {
            remember(image, for: url)
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                failures.withLock { _ = $0.insert(url) }
                return nil
            }
            guard let image = Self.thumbnail(from: data) else {
                failures.withLock { _ = $0.insert(url) }
                return nil
            }
            remember(image, for: url)
            Self.write(image, to: file)
            return image
        } catch {
            // A cancelled load (the card scrolled away) can be tried again later; anything else can't.
            if !Task.isCancelled, (error as? URLError)?.code != .cancelled {
                failures.withLock { _ = $0.insert(url) }
            }
            return nil
        }
    }

    private func remember(_ image: CGImage, for url: URL) {
        memory.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: Image I/O

    /// Downsamples and decodes in one step, without ever decoding the full-size image.
    private static func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Decode now, on this thread, rather than lazily on the main thread at first draw.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A thumbnail written earlier, decoded now rather than at first draw.
    private static func decode(contentsOf file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// JPEG, or PNG for images with transparency (JPEG would turn it black).
    private static func write(_ image: CGImage, to file: URL) {
        let hasAlpha = switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
        let type = hasAlpha ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}
