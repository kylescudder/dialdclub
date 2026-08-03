import SwiftUI

struct AIModelPickerView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss
    @Binding var provider: AIProvider
    @Binding var modelID: String
    @State private var searchText = ""

    private var matchingModels: [AIModel] {
        services.aiModelCatalog.models(for: provider).filter {
            searchText.isEmpty
                || $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Provider", selection: $provider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(matchingModels) { model in
                        Button {
                            modelID = model.id
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                Image(systemName: providerSymbol)
                                    .font(.title3)
                                    .foregroundStyle(Theme.Colors.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.displayName)
                                        .font(.body.weight(.semibold))
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
                            .padding(.vertical, 4)
                        }
                        .accessibilityLabel("\(model.displayName), \(model.description)")
                        .accessibilityAddTraits(model.id == modelID ? .isSelected : [])
                    }
                } header: {
                    Text("Available models")
                } footer: {
                    catalogStatus
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Choose a model")
            .searchable(text: $searchText, prompt: "Search models")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
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
                        .accessibilityLabel("Refresh models")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if let error = services.aiModelCatalog.lastRefreshError {
            Text(error)
        } else if let date = services.aiModelCatalog.lastUpdated {
            Text("Updated \(date.formatted(.relative(presentation: .named))). Saved models are available offline.")
        } else {
            Text("Saved models are available offline. Diald checks for newer models at most every six hours when you open Analyse.")
        }
    }

    private var providerSymbol: String {
        switch provider {
        case .openAI: "sparkles"
        case .anthropic: "a.circle.fill"
        }
    }
}
