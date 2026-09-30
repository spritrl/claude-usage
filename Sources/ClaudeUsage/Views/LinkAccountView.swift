import SwiftUI

struct LinkAccountView: View {
    @Environment(UsageStore.self) private var store
    @State private var manualCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lier ton compte Claude")
                    .font(.headline)
                Text("Claude Usage affiche ta consommation (session 5 h et semaine) dans la barre de menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .linking(let message) = store.phase {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(message).font(.callout)
                    Spacer()
                    Button("Annuler") { store.cancelLinking() }
                        .controlSize(.small)
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task { await store.linkViaClaudeCode() }
                    } label: {
                        Label("Lier via Claude Code", systemImage: "terminal")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    Text("Réutilise la session déjà ouverte dans le terminal. macOS peut demander l'accès au Trousseau : choisis « Toujours autoriser ».")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        store.startBrowserLogin()
                    } label: {
                        Label("Se connecter avec Claude", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    Text("Ouvre claude.ai dans le navigateur, puis revient automatiquement ici.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if store.manualLoginPending {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Colle le code affiché par claude.ai :")
                        .font(.caption)
                    HStack {
                        TextField("code#state", text: $manualCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .onSubmit(submit)
                        Button("Valider", action: submit)
                            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else if case .unlinked = store.phase {
                Button("Le navigateur ne revient pas ? Connexion manuelle") {
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
            HStack {
                Spacer()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
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
