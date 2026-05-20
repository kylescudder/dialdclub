import SwiftUI
import WidgetKit

private struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

private struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        completion(Timeline(entries: [QuickActionsEntry(date: Date())], policy: .never))
    }
}

private struct DashboardEntry: TimelineEntry {
    let date: Date
    let snapshot: BrewDashboardSnapshot?
}

private struct DashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(
            date: Date(),
            snapshot: BrewDashboardSnapshot(
                totalBrews: 18,
                averageRating: 4.2,
                averageExtractionSeconds: 31,
                favouriteMethodLabel: "Espresso",
                latestTitle: "Morning dial-in",
                latestMethodLabel: "Espresso",
                latestExtractionSeconds: 29,
                latestRating: 5,
                latestBrewedAt: Date(),
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(DashboardEntry(date: Date(), snapshot: WidgetSnapshotStore.dashboard()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        completion(Timeline(entries: [DashboardEntry(date: Date(), snapshot: WidgetSnapshotStore.dashboard())], policy: .never))
    }
}

private enum QuickAction: String, CaseIterable, Identifiable {
    case logBrew
    case startTimer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logBrew: "Log"
        case .startTimer: "Timer"
        }
    }

    var subtitle: String {
        switch self {
        case .logBrew: "Brew"
        case .startTimer: "Extraction"
        }
    }

    var systemImage: String {
        switch self {
        case .logBrew: "plus.circle.fill"
        case .startTimer: "stopwatch.fill"
        }
    }

    var url: URL {
        URL(string: "diald://shortcut/\(rawValue)")!
    }
}

private struct DialdQuickActionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickActionsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if family == .systemSmall {
                actionLink(.logBrew)
            } else {
                HStack(spacing: 10) {
                    ForEach(QuickAction.allCases) { action in
                        actionLink(action)
                    }
                }
            }
        }
        .widgetContainerStyle()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Diald")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("Coffee shortcuts")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func actionLink(_ action: QuickAction) -> some View {
        Link(destination: action.url) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.headline)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: family == .systemSmall ? 54 : 84, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct DialdDashboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DashboardEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if family == .systemSmall {
                    smallLayout(snapshot)
                } else {
                    mediumLayout(snapshot)
                }
            } else {
                emptyLayout
            }
        }
        .widgetContainerStyle()
    }

    private func smallLayout(_ snapshot: BrewDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Diald")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("\(snapshot.totalBrews)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("brews logged")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            Spacer(minLength: 0)
            Text(summaryText(snapshot))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumLayout(_ snapshot: BrewDashboardSnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Diald")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(snapshot.latestTitle ?? "No recent brew")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(snapshot.latestMethodLabel ?? snapshot.favouriteMethodLabel ?? "Start tracking recipes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                Text(lastBrewText(snapshot))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                metric("Brews", value: "\(snapshot.totalBrews)")
                metric("Avg", value: snapshot.averageRating.map { String(format: "%.1f", $0) } ?? "-")
                metric("Time", value: snapshot.averageExtractionSeconds.map { formatSeconds(Int($0)) } ?? "-")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var emptyLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Diald")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Log a brew to pin your latest recipe and stats here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func summaryText(_ snapshot: BrewDashboardSnapshot) -> String {
        if let rating = snapshot.averageRating {
            return "Average score \(String(format: "%.1f", rating))"
        }
        if let method = snapshot.favouriteMethodLabel {
            return "Mostly \(method)"
        }
        return "Ready for the next recipe"
    }

    private func lastBrewText(_ snapshot: BrewDashboardSnapshot) -> String {
        let time = snapshot.latestExtractionSeconds.map(formatSeconds) ?? "No time"
        let rating = snapshot.latestRating.map { " - \($0)/5" } ?? ""
        return "\(time)\(rating)"
    }

    private func formatSeconds(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

private extension View {
    func widgetContainerStyle() -> some View {
        padding(12)
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.09, blue: 0.06),
                        Color(red: 0.13, green: 0.34, blue: 0.23),
                        Color(red: 0.64, green: 0.32, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }
}

struct DialdQuickActionsWidget: Widget {
    let kind = "DialdQuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsProvider()) { entry in
            DialdQuickActionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Brew Shortcuts")
        .description("Quickly log a brew or start an extraction timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct DialdDashboardWidget: Widget {
    let kind = WidgetSnapshotStore.dashboardWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DashboardProvider()) { entry in
            DialdDashboardWidgetView(entry: entry)
        }
        .configurationDisplayName("Brew Dashboard")
        .description("Keep your latest brew and extraction stats on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct DialdWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DialdQuickActionsWidget()
        DialdDashboardWidget()
    }
}
