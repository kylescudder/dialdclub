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
                Text("\(matchingBrews.count) brew\(matchingBrews.count == 1 ? "" : "s") will be analysed only on this device.")
            }

            Section {
                Button {
                    Task { await runAnalysis() }
                } label: {
                    HStack {
                        if services.analysis.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(services.analysis.isLoading ? "Analysing…" : "Analyse my brews")
                    }
                }
                .disabled(services.analysis.isLoading || matchingBrews.isEmpty)

                if let error = services.analysis.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Analysis runs entirely on this device. No AI account, API key, or internet connection is required.")
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
