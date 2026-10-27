import SwiftUI

/// The window's content until there's a token: asks for one and checks it with Raindrop.
struct TokenPromptView: View {
    @Environment(AppSession.self) private var session
    @State private var form = TokenForm()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Connect to Raindrop")
                .font(.title)
            Text("Paste a test token from your Raindrop account. It's kept on this Mac only.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("How to get a test token", destination: RaindropServices.tokenHelpURL)
                Link("Open Raindrop's integrations", destination: RaindropServices.integrationsURL)
            }

            TokenField(form: form) { connect() }
                .frame(width: 380)

            HStack {
                #if DEBUG
                Button("Use Sample Data") { session.useSampleData() }
                #endif
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!form.canSubmit)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connect() {
        Task { await form.submit { try await session.connect(token: $0) } }
    }
}

/// Settings › Account: replace or remove the saved token.
struct TokenSettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var form = TokenForm()

    var body: some View {
        Form {
            Section {
                LabeledContent("Library", value: session.store?.sourceName ?? "Not connected")
                if session.usesEnvironmentToken {
                    Text("RAINDROP_TEST is set, so it's used instead of the saved token at launch.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TokenField(form: form) { connect() }
                HStack {
                    Link("How to get a test token", destination: RaindropServices.tokenHelpURL)
                    Spacer()
                    if session.savedToken != nil {
                        Button("Remove Token", role: .destructive) { session.disconnect() }
                    }
                    Button(session.savedToken == nil ? "Connect" : "Replace Token") { connect() }
                        .disabled(!form.canSubmit)
                }
            } header: {
                Text("Test Token")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func connect() {
        Task {
            await form.submit { try await session.connect(token: $0) }
            if form.error == nil { form.token = "" }
        }
    }
}

/// The token being typed and the result of checking it.
@Observable
private final class TokenForm {
    var token = ""
    private(set) var isChecking = false
    private(set) var error: String?

    var canSubmit: Bool {
        !isChecking && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit(_ connect: (String) async throws -> Void) async {
        guard canSubmit else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            try await connect(token)
            error = nil
        } catch RaindropAPIService.Failure.unauthorized {
            error = "Raindrop didn't accept this token."
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TokenField: View {
    @Bindable var form: TokenForm
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Test token", text: $form.token)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(onSubmit)
                if form.isChecking {
                    ProgressView().controlSize(.small)
                }
            }
            if let error = form.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

#Preview("Prompt") {
    TokenPromptView()
        .frame(width: 800, height: 500)
        .environment(AppSession())
}

#Preview("Settings") {
    TokenSettingsView()
        .environment(AppSession())
}
