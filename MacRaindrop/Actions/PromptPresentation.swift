import SwiftUI

extension View {
    /// Presents what `prompts` asks for (the edit and tags sheets, the delete confirmation)
    /// and the store's write failures.
    func presentsPrompts(_ prompts: ActionPrompts) -> some View {
        modifier(PromptPresentation(prompts: prompts))
    }
}

private struct PromptPresentation: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Bindable var prompts: ActionPrompts

    func body(content: Content) -> some View {
        content
            .sheet(item: $prompts.editing) { raindrop in
                EditRaindropSheet(raindrop: raindrop)
            }
            .sheet(item: $prompts.tagging) { request in
                AddTagsSheet(request: request)
            }
            .confirmationDialog(
                prompts.deletion.map { $0.ids.count == 1 ? "Delete this bookmark immediately?" : "Delete \($0.ids.count) bookmarks immediately?" } ?? "",
                isPresented: isPresented(\.deletion),
                presenting: prompts.deletion
            ) { request in
                Button("Delete", role: .destructive) {
                    Task { await store.attempt("Couldn't Delete Bookmarks") { try await store.delete(request.ids) } }
                }
            } message: { request in
                Text(request.includesOthers
                    ? "Bookmarks already in the Trash are deleted for good, and the others move to the Trash. You can't undo this."
                    : "You can't undo this.")
            }
            .alert(store.writeFailure?.title ?? "", isPresented: showsWriteFailure, presenting: store.writeFailure) { failure in
                Button("Try Again") { Task { await failure.retry() } }
                Button("OK", role: .cancel) {}
            } message: { failure in
                Text(failure.message)
            }
    }

    private func isPresented<Request>(_ keyPath: ReferenceWritableKeyPath<ActionPrompts, Request?>) -> Binding<Bool> {
        Binding {
            prompts[keyPath: keyPath] != nil
        } set: { isPresented in
            if !isPresented { prompts[keyPath: keyPath] = nil }
        }
    }

    private var showsWriteFailure: Binding<Bool> {
        Binding {
            store.writeFailure != nil
        } set: { isPresented in
            if !isPresented { store.writeFailure = nil }
        }
    }
}
