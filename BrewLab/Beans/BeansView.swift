import SwiftUI

struct BeansView: View {
    @EnvironmentObject private var services: AppServices
    @State private var showingAddBean = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(services.beans.beans) { bean in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bean.displayName)
                            .font(.headline)
                        Text([bean.origin, bean.process, bean.roastLevel?.label].compactMap { $0 }.joined(separator: " • "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.muted)
                        if let notes = bean.tastingNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.footnote)
                                .foregroundStyle(Theme.Colors.muted)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await services.beans.softDelete(bean) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if services.beans.beans.isEmpty {
                    ContentUnavailableView(
                        "No beans",
                        systemImage: "leaf",
                        description: Text("Add the coffee you are experimenting with.")
                    )
                }
            }
            .navigationTitle("Beans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddBean = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await services.beans.refresh() }
            .sheet(isPresented: $showingAddBean) {
                AddBeanView()
            }
        }
    }
}

private struct AddBeanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    @State private var name = ""
    @State private var roaster = ""
    @State private var origin = ""
    @State private var process = ""
    @State private var roastLevel: RoastLevel = .light

    var body: some View {
        NavigationStack {
            Form {
                Section("Coffee") {
                    TextField("Bean or lot name", text: $name)
                    TextField("Roaster", text: $roaster)
                    TextField("Origin", text: $origin)
                    TextField("Process", text: $process)
                    Picker("Roast", selection: $roastLevel) {
                        ForEach(RoastLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                }
            }
            .navigationTitle("Add bean")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await services.beans.create(
                                name: name,
                                roaster: roaster,
                                origin: origin,
                                process: process,
                                roastLevel: roastLevel
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || roaster.isEmpty)
                }
            }
        }
    }
}
