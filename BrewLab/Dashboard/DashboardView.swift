import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var services: AppServices
    @State private var showingAddBrew = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HeroStatsCard()
                    recentBrews
                }
                .padding()
            }
            .background(Theme.Colors.background)
            .navigationTitle("BrewLab")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddBrew = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Log brew")
                }
            }
            .refreshable { await services.refreshAll() }
            .sheet(isPresented: $showingAddBrew) {
                AddBrewView()
            }
        }
    }

    private var recentBrews: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recent brews")
                .font(.headline)
            if services.brews.brews.isEmpty {
                Card {
                    ContentUnavailableView(
                        "No brews yet",
                        systemImage: "cup.and.saucer",
                        description: Text("Log your first shot or filter brew to start comparing recipes.")
                    )
                }
            } else {
                ForEach(services.brews.brews) { brew in
                    BrewRowView(brew: brew)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task {
                                    await services.brews.softDelete(brew)
                                    await services.refreshBrewData()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }
}

private struct HeroStatsCard: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Dial-in board")
                            .font(.title2.bold())
                        Text("Keep extraction time, ratio, grind, and tasting notes in one place.")
                            .foregroundStyle(Theme.Colors.muted)
                            .font(.callout)
                    }
                    Spacer()
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.Colors.amber)
                }
                HStack {
                    StatPill(label: "Brews", value: "\(services.stats.stats.totalBrews)")
                    StatPill(
                        label: "Avg time",
                        value: services.stats.stats.averageExtractionSeconds.map { "\(Int($0))s" } ?? "-"
                    )
                    StatPill(
                        label: "Avg score",
                        value: services.stats.stats.averageRating.map { String(format: "%.1f", $0) } ?? "-"
                    )
                }
            }
        }
    }
}

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.Colors.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BrewRowView: View {
    let brew: BrewSession

    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(brew.title)
                        .font(.headline)
                    Text("\(brew.method.label) • \(brew.doseGrams, specifier: "%.1f")g in • \(brew.ratioText)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.muted)
                    if let notes = brew.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.muted)
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(brew.timeText)
                        .font(.title3.monospacedDigit().bold())
                    if let rating = brew.rating {
                        Text("\(rating)/5")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.amber)
                    }
                }
            }
        }
    }
}
