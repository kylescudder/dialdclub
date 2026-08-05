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
                            Text(analysisLabTitle)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(analysisLabSubtitle)
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            } header: {
                Text("Analysis lab")
            } footer: {
                Text(isActiveLabConfigured ? "Your API key is stored in Keychain and sent only to the selected provider." : "Choose a lab to add its API key, then choose one of its models.")
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
                .disabled(services.analysis.isLoading || matchingBrews.isEmpty || !services.aiSettings.canAnalyse(with: services.aiSettings.provider))

                if let error = services.analysis.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !result.isEmpty {
                Section {
                    Text(result)
                        .textSelection(.enabled)
                        .padding(.vertical, Theme.Spacing.xs)
                } header: {
                    Text("Recommendations")
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

    private var analysisLabTitle: String {
        isActiveLabConfigured ? selectedModelName : "Choose an analysis lab"
    }

    private var analysisLabSubtitle: String {
        isActiveLabConfigured
            ? services.aiSettings.provider.label
            : "Add a provider key to get started"
    }

    private var isActiveLabConfigured: Bool {
        services.aiSettings.canAnalyse(with: services.aiSettings.provider)
    }

    @ViewBuilder
    private var selectedLabIcon: some View {
        if isActiveLabConfigured {
            let lab = AILab.fallback.first { $0.provider == services.aiSettings.provider } ?? AILab.fallback[0]
            AILabLogo(lab: lab, size: 32)
        } else {
            Image(systemName: "flask.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
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

            Section {
                SecureField("\(lab.name) API key", text: keyBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if provider.needsEndpoint {
                    TextField("API endpoint", text: endpointBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                if services.aiSettings.hasAPIKey(for: provider) {
                    Button("Remove API key", role: .destructive) {
                        services.aiSettings.clearKey(for: provider)
                    }
                }
            } header: {
                Text("API key")
            } footer: {
                Text("Your key is stored only in Keychain on this device and is sent directly to \(lab.name) when you run an analysis.")
            }

            Section {
                LabeledContent("Selected model", value: selectedModelName)
                Button("Choose a model") {
                    showModelPicker = true
                }
                Button(services.aiSettings.provider == provider ? "Current analysis lab" : "Use \(lab.name) for analysis") {
                    services.aiSettings.provider = provider
                }
                .disabled(services.aiSettings.provider == provider || !services.aiSettings.canAnalyse(with: provider))
            } header: {
                Text("Analysis")
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
            set: { services.aiSettings.setAPIKey($0, for: provider) }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { services.aiSettings.endpoint(for: provider) },
            set: { services.aiSettings.setEndpoint($0, for: provider) }
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
