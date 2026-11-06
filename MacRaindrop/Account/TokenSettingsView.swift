import SwiftUI

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

#Preview("Settings") {
    TokenSettingsView()
        .environment(AppSession())
}
