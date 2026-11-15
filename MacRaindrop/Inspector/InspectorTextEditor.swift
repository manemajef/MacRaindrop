import SwiftUI

/// The inspector's edit mode for the text fields: title, description, note and link.
///
/// These are easy to change by accident, so the inspector shows them read-only until its
/// pencil button opens this. Nothing is saved until Save (⌘S), which waits for the server and
/// checks for changes made elsewhere, like the edit sheet. Cancel (Esc) drops the edits.
struct InspectorTextEditor: View {
    @Environment(LibraryStore.self) private var store
    @Bindable var draft: RaindropDraft
    /// Called after saving or cancelling, to leave edit mode.
    let done: () -> Void

    @FocusState private var focusesTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $draft.value.title, axis: .vertical)
                    .font(.title3.bold())
                    .lineLimit(1...4)
                    .focused($focusesTitle)
                TextField("Description", text: $draft.value.excerpt, axis: .vertical)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...6)
                Divider()
                TextField("Note", text: $draft.value.note, axis: .vertical)
                    .lineLimit(2...10)
                Divider()
                LinkField(link: $draft.value.link)
            }
            .textFieldStyle(.plain)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))

            if let errorMessage = draft.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: done)
                    .keyboardShortcut(.cancelAction)
                Button {
                    save(checkingForConflicts: true)
                } label: {
                    if draft.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s")
                .disabled(!draft.canSave(in: store))
            }
            .controlSize(.small)
        }
        .disabled(draft.isSaving)
        .onAppear { focusesTitle = true }
        .task { await draft.loadLatest(from: store) }
        .alert("Changed on Another Device", isPresented: $draft.showsConflict) {
            Button("Save Anyway") { save(checkingForConflicts: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This bookmark was changed elsewhere after you started editing. Saving replaces only the fields you edited here.")
        }
    }

    private func save(checkingForConflicts: Bool) {
        Task {
            if await draft.save(to: store, checkingForConflicts: checkingForConflicts) {
                done()
            }
        }
    }
}

#Preview {
    let store = LibraryStore.preview
    InspectorTextEditor(draft: RaindropDraft(raindrop: store.raindrops[0])) {}
        .padding()
        .frame(width: 320)
        .previewEnvironment(store)
}
