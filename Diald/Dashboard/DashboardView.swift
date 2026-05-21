import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var services: AppServices
    @State private var showingAddBrew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                recentBrews
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Diald")
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
