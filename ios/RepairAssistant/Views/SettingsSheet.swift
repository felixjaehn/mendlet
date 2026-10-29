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
                    Toggle("Demo-Modus (ohne Server)", isOn: $settings.demoMode).tint(Theme.thread)
                } footer: {
                    Text("Im Demo-Modus spielt die App echte, aufgezeichnete Modellantworten vom 28.10. ab, ohne Server und ohne Internet.")
                }
                if settings.demoMode {
                    Section {
                        Toggle("Schnell (für Videoaufnahmen)", isOn: $settings.fastReplay).tint(Theme.thread)
                        Toggle("Agenten-Lauf mit Fehlerbehebung zeigen", isOn: $settings.recoveryTrace).tint(Theme.thread)
                    } footer: {
                        Text("Spielt die echten Modellantworten in etwa 6 statt 25 Sekunden ab. Der Agenten-Lauf mit Fehlerbehebung (Jeans) zeigt einen echten Lauf, in dem SAM einen Serverfehler meldete und der Agent ausgewichen ist.")
                    }
                }
                Section("Demo-Szenario") {
                    Picker("Szenario", selection: $settings.scenarioRaw) {
                        ForEach(DemoScenario.allCases) { Text($0.title).tag($0.rawValue) }
                        if !settings.demoMode { Text("Keins (echtes Modell)").tag("") }
                    }
                    if !settings.demoMode {
                        Text("Im Live-Modus wird das Szenario als mock_scenario an den Server gesendet.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Server") {
                    TextField("http://localhost:8787", text: $settings.baseURLString)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button {
                        Task { await check() }
                    } label: {
                        HStack { Text("Verbindung testen"); Spacer(); if checking { ProgressView() } else if let status { Text(status).foregroundStyle(status.hasPrefix("OK") ? Theme.safe : Theme.stop) } }
                    }
                }
                Section("Daten") {
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
        guard let url = flow.settings.baseURL else { status = "Ungültige URL"; return }
        checking = true
        let ok = await LiveAPIClient(baseURL: url).health()
        checking = false
        status = ok ? "OK" : "Keine Antwort"
    }
}
