import SwiftUI
import Observation

/// The token being typed and the result of checking it.
@Observable
final class TokenForm {
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

/// The token text field, with a spinner while it's checked and the error if it fails.
struct TokenField: View {
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
