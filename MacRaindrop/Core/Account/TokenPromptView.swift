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

#Preview("Prompt") {
    TokenPromptView()
        .frame(width: 800, height: 500)
        .environment(AppSession())
}
