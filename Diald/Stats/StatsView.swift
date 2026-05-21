import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Extraction overview")
                            .font(.headline)
                        HStack {
                            MetricBlock(title: "Total", value: "\(services.stats.stats.totalBrews)")
                            MetricBlock(title: "Avg score", value: services.stats.stats.averageRating.map { String(format: "%.1f", $0) } ?? "-")
                            MetricBlock(title: "Avg time", value: services.stats.stats.averageExtractionSeconds.map { "\(Int($0))s" } ?? "-")
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading) {
                        Text("Recent extraction times")
                            .font(.headline)
                        Chart(services.brews.brews.prefix(20).reversed()) { brew in
                            LineMark(
                                x: .value("Brew", brew.brewedAt),
                                y: .value("Seconds", brew.extractionSeconds)
                            )
                            .foregroundStyle(Theme.Colors.green)
                            PointMark(
                                x: .value("Brew", brew.brewedAt),
                                y: .value("Seconds", brew.extractionSeconds)
                            )
                            .foregroundStyle(Theme.Colors.amber)
                        }
                        .frame(height: 220)
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Stats")
        .refreshable { await services.refreshAll() }
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
