import SwiftUI

struct AnalyseView: View {
    @EnvironmentObject private var services: AppServices
    @State private var filters = AnalysisFilters()
    @State private var result = ""

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
                TextField("Model", text: modelBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                NavigationLink("AI provider settings") {
                    AIProviderSettingsView()
                }
            } header: {
                Text("AI provider")
            } footer: {
                Text(services.aiSettings.hasActiveAPIKey ? "Your API key is stored in Keychain and sent only to the selected provider." : "Add a provider API key before analysing your brew data.")
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
                TextField("Model", text: modelBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use default for \(services.aiSettings.provider.label)") {
                    services.aiSettings.resetModelToProviderDefault()
                }
            }
        }
        .navigationTitle("AI provider")
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
}
