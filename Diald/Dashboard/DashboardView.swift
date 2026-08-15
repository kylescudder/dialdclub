import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var services: AppServices
    @State private var showingAddBrew = false
    @State private var startTimerOnOpen = false
    @State private var initialRecipe: BrewSession?
    @State private var brewToEdit: BrewSession?
    @State private var brewPendingDeletion: BrewSession?
    @State private var filters = BrewFilters()
    @State private var showingFilters = false

    var body: some View {
        List {
            readyToBrewSection
            filterSection
            brewsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Diald")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation {
                        showingFilters.toggle()
                    }
                } label: {
                    Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter brews")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startTimerOnOpen = false
                    initialRecipe = nil
                    showingAddBrew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Log brew")
            }
        }
        .refreshable { await services.refreshAll() }
        .sheet(isPresented: $showingAddBrew) {
            AddBrewView(
                startTimerOnAppear: startTimerOnOpen,
                initialRecipe: initialRecipe
            )
        }
        .sheet(item: $brewToEdit) { brew in
            AddBrewView(brewToEdit: brew)
        }
        .alert("Delete brew?", isPresented: Binding(
            get: { brewPendingDeletion != nil },
            set: { if !$0 { brewPendingDeletion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let brew = brewPendingDeletion else { return }
                Task {
                    await services.brews.softDelete(brew)
                    await services.refreshBrewData()
                    brewPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                brewPendingDeletion = nil
            }
        } message: {
            Text("This removes the brew from your records.")
        }
    }

    private var readyToBrewSection: some View {
        Section {
            ReadyToBrewCard(
                brew: latestBrew,
                beanName: latestBrew.flatMap(beanName(for:)),
                startBrew: {
                    startTimerOnOpen = true
                    initialRecipe = latestBrew
                    showingAddBrew = true
                }
            )
            .listRowInsets(EdgeInsets(
                top: Theme.Spacing.sm,
                leading: Theme.Spacing.lg,
                bottom: Theme.Spacing.sm,
                trailing: Theme.Spacing.lg
            ))
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var filterSection: some View {
        if showingFilters || filters.isActive {
            Section {
                BrewFilterView(filters: $filters, beans: services.beans.beans)
            } header: {
                BrewSectionHeader(title: "Filters")
            }
        }
    }

    private var brewsSection: some View {
        Section {
            if filteredBrews.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: filters.isActive ? "line.3.horizontal.decrease.circle" : "cup.and.saucer",
                    description: Text(emptyDescription)
                )
                .foregroundStyle(Theme.Colors.textSecondary)
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredBrews) { brew in
                    BrewRowView(brew: brew, beanName: beanName(for: brew))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            brewToEdit = brew
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                brewPendingDeletion = brew
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                brewToEdit = brew
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Theme.Colors.accent)
                        }
                        .contextMenu {
                            Button {
                                brewToEdit = brew
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                brewPendingDeletion = brew
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Theme.Colors.surface)
                }
            }
        } header: {
            HStack {
                Text("Recent Brews")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if filters.isActive {
                    Text("\(filteredBrews.count) of \(services.brews.brews.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private var filteredBrews: [BrewSession] {
        services.brews.brews.filter { filters.matches($0) }
    }

    private var latestBrew: BrewSession? {
        services.brews.brews.max { $0.brewedAt < $1.brewedAt }
    }

    private var emptyTitle: String {
        if services.brews.brews.isEmpty { return "No brews yet" }
        return "No matching brews"
    }

    private var emptyDescription: String {
        if services.brews.brews.isEmpty {
            return "Log your first shot or filter brew to start comparing recipes."
        }
        return "Adjust or clear filters to widen the results."
    }

    private func beanName(for brew: BrewSession) -> String? {
        guard let beanID = brew.beanID else { return nil }
        return services.beans.beans.first { $0.id == beanID }?.displayName
    }
}

private struct ReadyToBrewCard: View {
    let brew: BrewSession?
    let beanName: String?
    let startBrew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("READY TO BREW")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                        .tracking(0.8)

                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if let brew {
                HStack(spacing: 0) {
                    RecipeFact(value: String(format: "%.1fg", brew.doseGrams), label: "Dose")
                    Divider().frame(height: 34)
                    RecipeFact(value: brew.ratioText, label: "Ratio")
                    Divider().frame(height: 34)
                    RecipeFact(value: brew.timeText, label: "Time")
                }
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.background, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            }

            Button(action: startBrew) {
                Label(brew == nil ? "Start a brew" : "Brew again", systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Colors.separator.opacity(0.45))
        }
    }

    private var title: String {
        brew?.title ?? "Your next cup"
    }

    private var subtitle: String {
        guard let brew else {
            return "Start the timer and capture your first recipe."
        }

        let bean = beanName ?? "No bean selected"
        return "\(bean) \u{2022} \(brew.method.label)"
    }
}

private struct RecipeFact: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BrewSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.accent)
            .textCase(.uppercase)
    }
}

private struct BrewRowView: View {
    let brew: BrewSession
    let beanName: String?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(brew.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(detailText)
                    .footnoteSecondary()
                    .lineLimit(1)
                if let beanName {
                    Text(beanName)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                if let notes = brew.notes, !notes.isEmpty {
                    Text(notes)
                        .captionSecondary()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text(brew.timeText)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let rating = brew.rating {
                    Text("\(rating)/5")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.amber)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var detailText: String {
        "\(brew.method.label) • \(String(format: "%.1f", brew.doseGrams))g in • \(brew.ratioText)"
    }
}

private struct BrewFilterView: View {
    @Binding var filters: BrewFilters
    let beans: [CoffeeBean]

    var body: some View {
        Picker("Bean", selection: $filters.beanID) {
            Text("Any bean").tag(UUID?.none)
            ForEach(beans) { bean in
                Text(bean.displayName).tag(Optional(bean.id))
            }
        }

        Picker("Method", selection: $filters.method) {
            Text("Any method").tag(BrewMethod?.none)
            ForEach(BrewMethod.allCases) { method in
                Text(method.label).tag(Optional(method))
            }
        }

        Stepper(value: $filters.minimumExtractionSeconds, in: 0...900, step: 5) {
            LabeledContent("Minimum time", value: filters.minimumExtractionText)
        }

        Stepper(value: $filters.maximumExtractionSeconds, in: 0...900, step: 5) {
            LabeledContent("Maximum time", value: filters.maximumExtractionText)
        }

        Picker("Minimum rating", selection: $filters.minimumRating) {
            Text("Any rating").tag(Int?.none)
            ForEach(1...5, id: \.self) { rating in
                Text("\(rating)+").tag(Optional(rating))
            }
        }

        if filters.isActive {
            Button("Clear filters") {
                filters = BrewFilters()
            }
            .foregroundStyle(Theme.Colors.accent)
        }
    }
}

private struct BrewFilters {
    var beanID: UUID?
    var method: BrewMethod?
    var minimumExtractionSeconds = 0
    var maximumExtractionSeconds = 0
    var minimumRating: Int?

    var isActive: Bool {
        beanID != nil ||
            method != nil ||
            minimumExtractionSeconds > 0 ||
            maximumExtractionSeconds > 0 ||
            minimumRating != nil
    }

    var minimumExtractionText: String {
        minimumExtractionSeconds == 0 ? "Any" : format(seconds: minimumExtractionSeconds)
    }

    var maximumExtractionText: String {
        maximumExtractionSeconds == 0 ? "Any" : format(seconds: maximumExtractionSeconds)
    }

    func matches(_ brew: BrewSession) -> Bool {
        if let beanID, brew.beanID != beanID { return false }
        if let method, brew.method != method { return false }
        if minimumExtractionSeconds > 0, brew.extractionSeconds < minimumExtractionSeconds { return false }
        if maximumExtractionSeconds > 0, brew.extractionSeconds > maximumExtractionSeconds { return false }
        if let minimumRating, (brew.rating ?? 0) < minimumRating { return false }
        return true
    }

    private func format(seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
