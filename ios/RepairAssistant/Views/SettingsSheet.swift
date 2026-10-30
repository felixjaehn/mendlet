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
                    Toggle("Precision mode", isOn: $settings.precisionMode)
                } header: {
                    Text("Analysis")
                } footer: {
                    Text("Uses Muse Wonder to double-check every outline. Slower.")
                }
                Section {
                    Button("Delete all repairs", role: .destructive) { confirmClear = true }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Removes every photo and all progress from this device.")
                }
                Section {
                    NavigationLink("How Mendlet works") { HowItWorksView() }
                    HStack { Text("Version"); Spacer(); Text(version).foregroundStyle(Theme.inkSecondary) }
                        .contentShape(Rectangle())
                        .onTapGesture { taps += 1; if taps >= 5 { dev = true } }
                } header: {
                    Text("About")
                } footer: {
                    Text("Powered by Meta SAM 3.1, Muse Spark, Muse Wonder, Muse Image and Muse Voice.")
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
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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

/// The hidden "What happened" trace for the last analysis: every tool call with model and time.
struct HowItWorksView: View {
    @Environment(FlowModel.self) private var flow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if flow.agentSteps.isEmpty {
                    Text("Scan something and the steps of the analysis show up here.")
                        .font(.body).foregroundStyle(Theme.inkSecondary).lineSpacing(4)
                } else {
                    Text("Every analysis runs as a short chain of steps. This is the last one.")
                        .font(.body).foregroundStyle(Theme.ink).lineSpacing(4)
                    AgentTraceView(steps: flow.agentSteps, active: nil, replay: flow.settings.demoMode)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.margin).padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper)
        .navigationTitle("How Mendlet works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
