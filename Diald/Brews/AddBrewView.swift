import SwiftUI

struct AddBrewView: View {
    var startTimerOnAppear = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    @State private var draft = BrewDraft()
    @State private var isRunning = false
    @State private var startedAt: Date?
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var hasAppliedInitialTimerState = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Title", text: $draft.title)
                    Picker("Method", selection: $draft.method) {
                        ForEach(BrewMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    Picker("Bean", selection: $draft.beanID) {
                        Text("None").tag(UUID?.none)
                        ForEach(services.beans.beans) { bean in
                            Text(bean.displayName).tag(Optional(bean.id))
                        }
                    }
                }

                Section("Variables") {
                    Stepper(value: $draft.doseGrams, in: 5...40, step: 0.5) {
                        LabeledContent("Dose", value: "\(draft.doseGrams, specifier: "%.1f")g")
                    }
                    OptionalDoubleField(title: "Yield", suffix: "g", value: $draft.yieldGrams)
                    OptionalDoubleField(title: "Water", suffix: "g", value: $draft.waterGrams)
                    OptionalDoubleField(title: "Temperature", suffix: "C", value: $draft.waterTemperatureC)
                    TextField("Grind setting", text: $draft.grindSetting)
                }

                Section("Extraction") {
                    HStack {
                        Text("\(draft.extractionSeconds / 60):" + String(format: "%02d", draft.extractionSeconds % 60))
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                        Spacer()
                        Button(isRunning ? "Stop" : "Start") {
                            toggleTimer()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Stepper(value: $draft.extractionSeconds, in: 1...900) {
                        Text("Manual time")
                    }
                }
                .onReceive(timer) { _ in
                    guard isRunning, let startedAt else { return }
                    draft.extractionSeconds = max(1, Int(Date().timeIntervalSince(startedAt)))
                }

                Section("Taste") {
                    Picker("Rating", selection: $draft.rating) {
                        Text("Unrated").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag(Optional($0)) }
                    }
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log brew")
            .onAppear {
                guard startTimerOnAppear, !hasAppliedInitialTimerState else { return }
                hasAppliedInitialTimerState = true
                draft.extractionSeconds = 1
                if !isRunning { toggleTimer() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await services.brews.create(draft)
                            await services.refreshBrewData()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func toggleTimer() {
        if isRunning {
            isRunning = false
        } else {
            startedAt = Date().addingTimeInterval(TimeInterval(-draft.extractionSeconds))
            isRunning = true
        }
    }
}

private struct OptionalDoubleField: View {
    let title: String
    let suffix: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .onAppear {
                    text = value.map { String(format: "%.1f", $0) } ?? ""
                }
                .onChange(of: text) { _, newValue in
                    value = Double(newValue)
                }
            Text(suffix)
                .foregroundStyle(Theme.Colors.muted)
        }
    }
}
