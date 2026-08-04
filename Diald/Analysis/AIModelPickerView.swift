import SwiftUI

struct AIModelPickerView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss
    @Binding var provider: AIProvider
    @Binding var modelID: String
    @State private var selectedLab: AILab?
    @State private var searchText = ""

    private var matchingLabs: [AILab] {
        services.aiModelCatalog.labs.filter {
            searchText.isEmpty
                || $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var matchingModels: [AIModel] {
        guard let provider = selectedLab?.provider else { return [] }
        return services.aiModelCatalog.models(for: provider).filter {
            searchText.isEmpty
                || $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let lab = selectedLab {
                    modelShelf(for: lab)
                } else {
                    labShelf
                }
            }
            .navigationTitle(selectedLab?.name ?? "Choose a lab")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: selectedLab == nil ? "Search labs" : "Search models")
            .onChange(of: selectedLab) { _, _ in searchText = "" }
            .toolbar { toolbar }
        }
    }

    private var labShelf: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "flask.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start with a lab")
                            .font(.headline)
                        Text("Choose where your analysis model comes from.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            labSection("Connected labs", labs: matchingLabs.filter(\.isConnected))
            labSection("Explore more labs", labs: matchingLabs.filter { !$0.isConnected })

            Section {
                catalogStatus
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func labSection(_ title: String, labs: [AILab]) -> some View {
        if !labs.isEmpty {
            Section(title) {
                ForEach(labs) { lab in
                    Button { selectedLab = lab } label: {
                        labRow(lab)
                    }
                    .accessibilityLabel("\(lab.name), \(lab.subtitle), \(lab.isConnected ? "connected" : "not connected")")
                }
            }
        }
    }

    private func labRow(_ lab: AILab) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            AILabLogo(lab: lab)
            VStack(alignment: .leading, spacing: 3) {
                Text(lab.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(lab.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Text(lab.isConnected ? "Connected" : "Explore")
                .font(.caption.weight(.medium))
                .foregroundStyle(lab.isConnected ? Theme.Colors.accent : Theme.Colors.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func modelShelf(for lab: AILab) -> some View {
        if let provider = lab.provider {
            List {
                Section {
                    ForEach(matchingModels) { model in
                        Button {
                            self.provider = provider
                            modelID = model.id
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                AILabLogo(lab: lab, size: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.displayName)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(model.description)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                if provider == self.provider, model.id == modelID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityLabel("\(model.displayName), \(model.description)")
                        .accessibilityAddTraits(provider == self.provider && model.id == modelID ? .isSelected : [])
                    }
                } header: {
                    Text("Available models")
                } footer: {
                    catalogStatus
                }
            }
            .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView {
                Label("\(lab.name) isn't connected", systemImage: "plug.disconnected")
            } description: {
                Text("Diald can display this lab today, but analysis needs its own API adapter and a secure key flow before its models can run.")
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if selectedLab == nil {
                Button("Close") { dismiss() }
            } else {
                Button {
                    selectedLab = nil
                } label: {
                    Label("All labs", systemImage: "chevron.left")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if services.aiModelCatalog.isRefreshing {
                ProgressView()
            } else {
                Button {
                    Task { await services.aiModelCatalog.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh model catalog")
            }
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if let error = services.aiModelCatalog.lastRefreshError {
            Text(error)
        } else if let date = services.aiModelCatalog.lastUpdated {
            Text("Updated \(date.formatted(.relative(presentation: .named))). Saved catalogs are available offline.")
        } else {
            Text("Saved catalogs are available offline. Diald checks for newer models at most every six hours when you open Analyse.")
        }
    }
}

struct AILabLogo: View {
    let lab: AILab
    var size: CGFloat = 34

    var body: some View {
        Image(logoAssetName)
            .resizable()
            .scaledToFit()
            .padding(size * 0.2)
            .background(.white, in: tile)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
    }

    private var logoAssetName: String {
        switch lab.id {
        case "openai": "OpenAIBlossom"
        case "anthropic": "AnthropicLogo"
        case "google": "GoogleLogo"
        case "xai": "XAILogo"
        case "meta": "MetaLogo"
        case "mistral": "MistralLogo"
        case "deepseek": "DeepSeekLogo"
        case "cohere": "CohereLogo"
        case "ai21": "AI21Logo"
        case "qwen": "QwenLogo"
        case "moonshot": "MoonshotLogo"
        case "minimax": "MiniMaxLogo"
        case "perplexity": "PerplexityLogo"
        case "bedrock": "AWSLogo"
        case "azure": "AzureLogo"
        case "groq": "GroqLogo"
        case "together": "TogetherLogo"
        case "fireworks": "FireworksLogo"
        case "nvidia": "NVIDIALogo"
        case "openrouter": "OpenRouterLogo"
        default: "AppLogoIcon"
        }
    }
}

struct AIProviderLogo: View {
    let provider: AIProvider
    var size: CGFloat = 32

    var body: some View {
        AILabLogo(
            lab: provider == .openAI
                ? AILab.fallback.first { $0.provider == .openAI }!
                : AILab.fallback.first { $0.provider == .anthropic }!,
            size: size
        )
    }
}
