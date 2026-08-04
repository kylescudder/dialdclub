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
                Button {
                    showModelPicker = true
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        selectedLabIcon
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
                Text("Analysis lab")
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

    @ViewBuilder
    private var selectedLabIcon: some View {
        AILabLogo(
            lab: services.aiSettings.provider == .openAI
                ? AILab.fallback.first { $0.provider == .openAI }!
                : AILab.fallback.first { $0.provider == .anthropic }!,
            size: 32
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

    private var analysisLabs: [AILab] {
        services.aiModelCatalog.labs.filter(\.isConnected)
    }

    private var catalogLabs: [AILab] {
        services.aiModelCatalog.labs.filter { !$0.isConnected }
    }

    var body: some View {
        List {
            Section {
                Text("Set up the lab you want to analyse your brew data. Keys stay in Keychain on this device.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Section("Ready for analysis") {
                ForEach(analysisLabs) { lab in
                    NavigationLink {
                        if let provider = lab.provider {
                            AIProviderConnectionView(lab: lab, provider: provider)
                        }
                    } label: {
                        labRow(lab, status: connectionStatus(for: lab))
                    }
                }
            }

            Section("Model catalogue") {
                ForEach(catalogLabs) { lab in
                    NavigationLink {
                        AICatalogLabView(lab: lab)
                    } label: {
                        labRow(lab, status: "Catalogue only")
                    }
                }
            } footer: {
                Text("These labs are shown so the catalogue can grow without an app update. They cannot be added as an analysis provider until Diald has that lab's request adapter and authentication flow.")
            }
        }
        .navigationTitle("Analysis labs")
        .task {
            await services.aiModelCatalog.refresh()
        }
    }

    private func labRow(_ lab: AILab, status: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            AILabLogo(lab: lab)
            VStack(alignment: .leading, spacing: 3) {
                Text(lab.name)
                    .font(.body.weight(.semibold))
                Text(lab.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(status == "Active" ? Theme.Colors.accent : Theme.Colors.textSecondary)
        }
        .padding(.vertical, 3)
    }

    private func connectionStatus(for lab: AILab) -> String {
        guard let provider = lab.provider else { return "Catalogue only" }
        if services.aiSettings.provider == provider { return "Active" }
        return services.aiSettings.hasAPIKey(for: provider) ? "Ready" : "Set up"
    }
}

struct AIProviderConnectionView: View {
    @EnvironmentObject private var services: AppServices
    let lab: AILab
    let provider: AIProvider
    @State private var showModelPicker = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    AILabLogo(lab: lab, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lab.name)
                            .font(.headline)
                        Text(lab.subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            Section("API key") {
                SecureField("\(lab.name) API key", text: keyBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if services.aiSettings.hasAPIKey(for: provider) {
                    Button("Remove API key", role: .destructive) {
                        services.aiSettings.clearKey(for: provider)
                    }
                }
            } footer: {
                Text("Your key is stored only in Keychain on this device and is sent directly to \(lab.name) when you run an analysis.")
            }

            Section("Analysis") {
                LabeledContent("Selected model", value: selectedModelName)
                Button("Choose a model") {
                    showModelPicker = true
                }
                Button(services.aiSettings.provider == provider ? "Current analysis lab" : "Use \(lab.name) for analysis") {
                    services.aiSettings.provider = provider
                }
                .disabled(services.aiSettings.provider == provider || !services.aiSettings.hasAPIKey(for: provider))
            }
        }
        .navigationTitle(lab.name)
        .sheet(isPresented: $showModelPicker) {
            AIProviderModelPickerView(provider: provider, modelID: modelBinding)
                .environmentObject(services)
        }
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { services.aiSettings.apiKey(for: provider) },
            set: { value in
                switch provider {
                case .openAI: services.aiSettings.openAIKey = value
                case .anthropic: services.aiSettings.anthropicKey = value
                }
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { services.aiSettings.provider == provider ? services.aiSettings.model : provider.defaultModel },
            set: { model in
                services.aiSettings.provider = provider
                services.aiSettings.model = model
            }
        )
    }

    private var selectedModelName: String {
        let model = services.aiSettings.provider == provider ? services.aiSettings.model : provider.defaultModel
        return services.aiModelCatalog.models(for: provider)
            .first(where: { $0.id == model })?
            .displayName ?? model
    }
}

struct AIProviderModelPickerView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss
    let provider: AIProvider
    @Binding var modelID: String

    var body: some View {
        NavigationStack {
            List(services.aiModelCatalog.models(for: provider)) { model in
                Button {
                    modelID = model.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.displayName)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(model.description)
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        if model.id == modelID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                }
            }
            .navigationTitle("Choose a model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AICatalogLabView: View {
    let lab: AILab

    var body: some View {
        ContentUnavailableView {
            Label("\(lab.name) is not available for analysis yet", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("Diald has a place for \(lab.name) in the model catalogue, but it does not yet have the API adapter or authentication flow needed to accept a key and run an analysis.")
        }
        .navigationTitle(lab.name)
        .padding(.horizontal, Theme.Spacing.xl)
    }
}
