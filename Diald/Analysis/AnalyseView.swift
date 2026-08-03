import SwiftUI

struct AnalyseView: View {
    @EnvironmentObject private var services: AppServices
    @State private var filters = AnalysisFilters()
    @State private var result = ""
    @State private var showModelPicker = false

    private var matchingBrews: [BrewSession] {
        services.brews.brews.filter(filters.matches)
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Start", selection: $filters.startDate, displayedComponents: .date)
                DatePicker("End", selection: $filters.endDate, displayedComponents: .date)
                Picker("Bean", selection: $filters.beanID) {
                    Text("Any bean").tag(UUID?.none)
                    ForEach(services.beans.beans) { bean in
                        Text(bean.displayName).tag(Optional(bean.id))
                    }
                }
                Picker("Method", selection: $filters.method) {
                    Text("Any method").tag(BrewMethod?.none)
                    ForEach(BrewMethod.allCases) { method in
                        Text(method.label).tag(Optional(method))
                    }
                }
                Picker("Minimum rating", selection: $filters.minimumRating) {
                    Text("Any rating").tag(Int?.none)
                    ForEach(1...5, id: \.self) { rating in
                        Text("\(rating)+").tag(Optional(rating))
                    }
                }
                Toggle("Include tasting notes", isOn: $filters.includeNotes)
            } header: {
                Text("Data filters")
            } footer: {
                Text("\(matchingBrews.count) brew\(matchingBrews.count == 1 ? "" : "s") will be sent to your selected AI provider.")
            }

            Section {
                Picker("Provider", selection: providerBinding) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                Button {
                    showModelPicker = true
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "cpu")
                            .foregroundStyle(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedModelName)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(services.aiSettings.provider.label)
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                NavigationLink("AI provider settings") {
                    AIProviderSettingsView()
                }
            } header: {
                Text("AI provider")
            } footer: {
                Text(services.aiSettings.hasActiveAPIKey ? "Your API key is stored in Keychain and sent only to the selected provider." : "Browse the current model catalog without a key. Add a provider API key only when you’re ready to analyse brew data.")
            }

            Section {
                Button {
                    Task { await runAnalysis() }
                } label: {
                    HStack {
                        if services.analysis.isLoading { ProgressView() }
                        Text(services.analysis.isLoading ? "Analysing…" : "Analyse my brews")
                    }
                }
                .disabled(services.analysis.isLoading || matchingBrews.isEmpty || !services.aiSettings.hasActiveAPIKey)

                if let error = services.analysis.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !result.isEmpty {
                Section("Recommendations") {
                    Text(result)
                        .textSelection(.enabled)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .navigationTitle("Analyse")
        .refreshable { await services.refreshAll() }
        .task { await services.aiModelCatalog.refresh() }
        .sheet(isPresented: $showModelPicker) {
            AIModelPickerView(provider: providerBinding, modelID: modelBinding)
                .environmentObject(services)
        }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: { services.aiSettings.provider },
            set: { services.aiSettings.provider = $0 }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { services.aiSettings.model },
            set: { services.aiSettings.model = $0 }
        )
    }

    private var selectedModelName: String {
        services.aiModelCatalog.models(for: services.aiSettings.provider)
            .first(where: { $0.id == services.aiSettings.model })?
            .displayName ?? services.aiSettings.model
    }

    private func runAnalysis() async {
        if let response = await services.analysis.analyse(
            brews: services.brews.brews,
            beans: services.beans.beans,
            filters: filters
        ) {
            result = response
        }
    }
}

struct AIProviderSettingsView: View {
    @EnvironmentObject private var services: AppServices
    @State private var showModelPicker = false

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: providerBinding) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                SecureField("OpenAI API key", text: openAIKeyBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Anthropic API key", text: anthropicKeyBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Clear selected provider key", role: .destructive) {
                    services.aiSettings.clearActiveKey()
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("Diald supports bring-your-own OpenAI or Anthropic API keys today. Account OAuth can be wired here once provider OAuth credentials and redirect configuration are available.")
            }

            Section("Model") {
                Button {
                    showModelPicker = true
                } label: {
                    LabeledContent("Selected", value: selectedModelName)
                }
                Button("Use default for \(services.aiSettings.provider.label)") {
                    services.aiSettings.resetModelToProviderDefault()
                }
            }
        }
        .navigationTitle("AI provider")
        .sheet(isPresented: $showModelPicker) {
            AIModelPickerView(provider: providerBinding, modelID: modelBinding)
                .environmentObject(services)
        }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(
            get: { services.aiSettings.provider },
            set: { services.aiSettings.provider = $0 }
        )
    }

    private var openAIKeyBinding: Binding<String> {
        Binding(
            get: { services.aiSettings.openAIKey },
            set: { services.aiSettings.openAIKey = $0 }
        )
    }

    private var anthropicKeyBinding: Binding<String> {
        Binding(
            get: { services.aiSettings.anthropicKey },
            set: { services.aiSettings.anthropicKey = $0 }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { services.aiSettings.model },
            set: { services.aiSettings.model = $0 }
        )
    }

    private var selectedModelName: String {
        services.aiModelCatalog.models(for: services.aiSettings.provider)
            .first(where: { $0.id == services.aiSettings.model })?
            .displayName ?? services.aiSettings.model
    }
}
