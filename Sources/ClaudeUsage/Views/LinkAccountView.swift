import SwiftUI

struct LinkAccountView: View {
    @Environment(UsageStore.self) private var store
    @State private var manualCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Link your Claude account"))
                    .font(.headline)
                Text(tr("Claude Usage shows your consumption (5-hour session and weekly) in the menu bar."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .linking(let message) = store.phase {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(message).font(.callout)
                    Spacer()
                    Button(tr("Cancel")) { store.cancelLinking() }
                        .controlSize(.small)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task { await store.linkViaClaudeCode() }
                    } label: {
                        Label(tr("Link via Claude Code"), systemImage: "terminal")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    Text(tr("Reuses the session already open in your terminal. macOS may ask for Keychain access: choose “Always Allow”."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        store.startBrowserLogin()
                    } label: {
                        Label(tr("Sign in with Claude"), systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    Text(tr("Opens claude.ai in your browser, then comes back here automatically."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if store.manualLoginPending {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Paste the code shown by claude.ai:"))
                        .font(.caption)
                    HStack {
                        TextField("code#state", text: $manualCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .onSubmit(submit)
                        Button(tr("Submit"), action: submit)
                            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else if case .unlinked = store.phase {
                Button(tr("Browser not coming back? Sign in manually")) {
                    store.startManualLogin()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack(alignment: .top) {
                LaunchAtLoginToggle()
                Spacer()
                Button(tr("Quit")) { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
    }

    private func submit() {
        let code = manualCode
        manualCode = ""
        Task { await store.submitManualCode(code) }
    }
}
