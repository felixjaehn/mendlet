import SwiftUI

struct SettingsSheet: View {
    @Environment(FlowModel.self) private var flow
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var checking = false

    var body: some View {
        @Bindable var settings = flow.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Use server", isOn: Binding(get: { !settings.demoMode }, set: { settings.demoMode = !$0 })).tint(Theme.thread)
                }
                if !settings.demoMode {
                    Section("Server") {
                        TextField("http://localhost:8787", text: $settings.baseURLString)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Button {
                            Task { await check() }
                        } label: {
                            HStack { Text("Verbindung testen"); Spacer(); if checking { ProgressView() } else if let status { Text(status).foregroundStyle(status.hasPrefix("OK") ? Theme.safe : Theme.stop) } }
                        }
                        Toggle("Präzisionsmodus (Muse Wonder)", isOn: $settings.precisionMode).tint(Theme.thread)
                    }
                }
                Section {
                    Button("Verlauf löschen", role: .destructive) { flow.store.clearHistory() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func check() async {
        guard let url = flow.settings.baseURL else { status = tr("Ungültige URL"); return }
        checking = true
        let ok = await LiveAPIClient(baseURL: url).health()
        checking = false
        status = ok ? "OK" : tr("Keine Antwort")
    }
}
