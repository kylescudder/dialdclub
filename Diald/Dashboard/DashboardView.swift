import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var services: AppServices
    @State private var showingAddBrew = false
    @State private var brewToEdit: BrewSession?
    @State private var brewPendingDeletion: BrewSession?
    @State private var filters = BrewFilters()
    @State private var showingFilters = false

    var body: some View {
        List {
            if showingFilters || filters.isActive {
                Section {
                    BrewFilterView(filters: $filters, beans: services.beans.beans)
                }
            }

            Section {
                if filteredBrews.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: filters.isActive ? "line.3.horizontal.decrease.circle" : "cup.and.saucer",
                        description: Text(emptyDescription)
                    )
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
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    brewToEdit = brew
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Theme.Colors.green)
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
                    }
                }
            } header: {
                HStack {
                    Text("Recent brews")
                    Spacer()
                    if filters.isActive {
                        Text("\(filteredBrews.count) of \(services.brews.brews.count)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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

    private var filteredBrews: [BrewSession] {
        services.brews.brews.filter { filters.matches($0) }
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

private struct BrewRowView: View {
    let brew: BrewSession
    let beanName: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(brew.title)
                    .font(.headline)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.muted)
                if let beanName {
                    Text(beanName)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.muted)
                }
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
        .padding(.vertical, 4)
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
