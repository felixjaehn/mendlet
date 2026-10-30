import SwiftUI

struct SettingsSheet: View {
    @Environment(FlowModel.self) private var flow
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var checking = false
    @State private var taps = 0
    @State private var confirmClear = false
    @State private var dev = UserDefaults.standard.bool(forKey: "showDev")

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    var body: some View {
        @Bindable var settings = flow.settings
        NavigationStack {
            List {
                Section {
                    HStack { Text("Photo analysis"); Spacer(); Text("On our server").foregroundStyle(Theme.inkSecondary) }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Photos are sent to the analysis server only to assess the repair.")
                }
                Section {
                    Button("Delete all repairs", role: .destructive) { confirmClear = true }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Removes every photo and all progress from this device.")
                }
                Section {
                    HStack { Text("Mendlet"); Spacer(); Text(version).foregroundStyle(Theme.inkSecondary) }
                        .contentShape(Rectangle())
                        .onTapGesture { taps += 1; if taps >= 5 { dev = true } }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Powered by Meta SAM 3.1, Muse Spark, Muse Image")
                            .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }
                } header: {
                    Text("About")
                }
                if dev {
                    Section("Developer") {
                        Toggle("Use server", isOn: Binding(get: { !settings.demoMode }, set: { settings.demoMode = !$0 }))
                        if !settings.demoMode {
                            TextField("http://localhost:8787", text: $settings.baseURLString)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            Button {
                                Task { await check() }
                            } label: {
                                HStack { Text("Test connection"); Spacer(); if checking { ProgressView() } else if let status { Text(status).foregroundStyle(Theme.inkSecondary) } }
                            }
                            Toggle("Precision mode", isOn: $settings.precisionMode)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete all repairs? Photos and progress will be removed.", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all repairs", role: .destructive) { flow.store.clearHistory() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    private func check() async {
        guard let url = flow.settings.baseURL else { status = "Invalid URL"; return }
        checking = true
        let ok = await LiveAPIClient(baseURL: url).health()
        checking = false
        status = ok ? "OK" : "No response"
    }
}
