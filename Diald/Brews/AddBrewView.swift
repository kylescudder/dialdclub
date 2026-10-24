import SwiftUI

struct AddBrewView: View {
    var startTimerOnAppear = false
    var brewToEdit: BrewSession?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var services: AppServices
    @State private var draft = BrewDraft()
    @State private var isRunning = false
    @State private var startedAt: Date?
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var hasAppliedInitialTimerState = false
    @State private var showPaywall = false
    @State private var creationFailure: BrewCreationError?
    @State private var showTimerScreen = false

    init(
        startTimerOnAppear: Bool = false,
        brewToEdit: BrewSession? = nil,
        initialRecipe: BrewSession? = nil
    ) {
        self.startTimerOnAppear = startTimerOnAppear
        self.brewToEdit = brewToEdit

        var initialDraft = (brewToEdit ?? initialRecipe).map(BrewDraft.init(brew:)) ?? BrewDraft()
        if brewToEdit == nil, initialRecipe != nil {
            initialDraft.brewedAt = Date()
        }
        _draft = State(initialValue: initialDraft)
    }

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
                    DatePicker("Brewed at", selection: $draft.brewedAt)
                }

                Section("Variables") {
                    Stepper(value: $draft.doseGrams, in: 5...40, step: 0.5) {
                        LabeledContent("Dose", value: String(format: "%.1fg", draft.doseGrams))
                    }
                    OptionalDoubleField(title: "Yield", suffix: "g", value: $draft.yieldGrams)
                    OptionalDoubleField(title: "Water", suffix: "g", value: $draft.waterGrams)
                    OptionalDoubleField(title: "Temperature", suffix: "C", value: $draft.waterTemperatureC)
                    TextField("Grind setting", text: $draft.grindSetting)
                }

                Section("Extraction") {
                    HStack {
                        Text(timeText)
                            .font(.system(size: 44, weight: .bold, design: .monospaced))
                        Spacer()
                        Button("Open timer") {
                            showTimerScreen = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    ManualSecondsField(title: "Manual time", seconds: $draft.extractionSeconds)
                    Stepper(value: $draft.extractionSeconds, in: 0...900, step: 5) {
                        Text("Adjust by 5 seconds")
                    }
                }
                .onReceive(timer) { _ in
                    updateRunningTimer()
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
            .navigationTitle(brewToEdit == nil ? "Log brew" : "Edit brew")
            .onAppear {
                guard startTimerOnAppear, !hasAppliedInitialTimerState else { return }
                hasAppliedInitialTimerState = true
                draft.extractionSeconds = 0
                showTimerScreen = true
                if !isRunning { toggleTimer() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPaywall) {
                SubscriptionPaywallView()
            }
            .alert(item: $creationFailure) { error in
                creationAlert(for: error)
            }
            .fullScreenCover(isPresented: $showTimerScreen) {
                CoffeeTimerScreen(
                    seconds: $draft.extractionSeconds,
                    isRunning: $isRunning,
                    startedAt: $startedAt,
                    toggleTimer: toggleTimer
                )
            }
        }
    }

    private var timeText: String {
        "\(draft.extractionSeconds / 60):" + String(format: "%02d", draft.extractionSeconds % 60)
    }

    private func updateRunningTimer() {
        guard isRunning, let startedAt else { return }
        draft.extractionSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
    }

    private func toggleTimer() {
        if isRunning {
            updateRunningTimer()
            isRunning = false
        } else {
            startedAt = Date().addingTimeInterval(TimeInterval(-draft.extractionSeconds))
            isRunning = true
        }
    }

    private func save() async {
        guard canSave else { return }
        if let brewToEdit {
            await services.brews.update(brewToEdit, with: draft)
        } else {
            switch await services.canCreateNewExtraction() {
            case .allowed:
                break
            case .limitReached:
                showPaywall = true
                return
            case .subscriptionVerificationPending:
                handleCreationError(.subscriptionVerificationPending)
                return
            case .failed(let error):
                handleCreationError(error)
                return
            }

            do {
                try await services.brews.create(draft)
            } catch let error as BrewCreationError {
                handleCreationError(error)
                return
            } catch {
                handleCreationError(.unknownFailure)
                return
            }
        }
        await services.refreshBrewData()
        dismiss()
    }

    private func handleCreationError(_ error: BrewCreationError) {
        if case .paywall = BrewCreationFailurePresentation.forError(error) {
            showPaywall = true
        } else {
            creationFailure = error
        }
    }

    private func creationAlert(for error: BrewCreationError) -> Alert {
        switch BrewCreationFailurePresentation.forError(error) {
        case .paywall:
            return Alert(title: Text("Free extraction limit reached"))
        case .verification(let title, let message):
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .default(Text("Retry")) {
                    Task {
                        await services.billing.syncEntitlements()
                        await save()
                    }
                },
                secondaryButton: .cancel()
            )
        case .alert(let title, let message):
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.doseGrams > 0
            && draft.extractionSeconds > 0
    }
}


private struct CoffeeTimerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var seconds: Int
    @Binding var isRunning: Bool
    @Binding var startedAt: Date?
    let toggleTimer: () -> Void
    @State private var timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.07, blue: 0.04), Color(red: 0.32, green: 0.18, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            CoffeeDripAnimation(isRunning: isRunning)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Extraction timer")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text(isRunning ? "Coffee is dripping…" : "Ready when you are")
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.white.opacity(0.16), in: Circle())
                    }
                }

                Spacer()

                Text(timeText)
                    .font(.system(size: 92, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

                ManualSecondsField(title: "Type seconds", seconds: $seconds, textColor: .white)
                    .padding()
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    .disabled(isRunning)

                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        seconds = 0
                        startedAt = isRunning ? Date() : nil
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        toggleTimer()
                    } label: {
                        Label(isRunning ? "Stop" : "Start", systemImage: isRunning ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.amber)
                }
                .controlSize(.large)

                Spacer()
            }
            .padding(Theme.Spacing.lg)
        }
        .onReceive(timer) { _ in
            guard isRunning, let startedAt else { return }
            seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        }
    }

    private var timeText: String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

private struct CoffeeDripAnimation: View {
    let isRunning: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerX = size.width / 2
                let topY = size.height * 0.18
                let cupY = size.height * 0.68
                let streamOpacity = isRunning ? 0.85 : 0.25

                var stream = Path()
                stream.move(to: CGPoint(x: centerX, y: topY))
                stream.addCurve(
                    to: CGPoint(x: centerX + sin(time * 2) * 8, y: cupY),
                    control1: CGPoint(x: centerX - 18, y: topY + 120),
                    control2: CGPoint(x: centerX + 20, y: cupY - 160)
                )
                context.stroke(stream, with: .color(Theme.Colors.amber.opacity(streamOpacity)), lineWidth: 5)

                for index in 0..<7 {
                    let phase = isRunning ? (time * 0.42 + Double(index) / 7).truncatingRemainder(dividingBy: 1) : Double(index) / 7
                    let y = topY + (cupY - topY) * phase
                    let wobble = sin(time * 3 + Double(index)) * 18
                    let radius = 7 + sin(time * 5 + Double(index)) * 2
                    let rect = CGRect(x: centerX + wobble - radius, y: y - radius, width: radius * 2, height: radius * 2.8)
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.Colors.amber.opacity(isRunning ? 0.95 : 0.35)))
                }

                let cupRect = CGRect(x: centerX - 118, y: cupY, width: 236, height: 92)
                context.fill(Path(roundedRect: cupRect, cornerRadius: 34), with: .color(.white.opacity(0.16)))
                context.stroke(Path(roundedRect: cupRect, cornerRadius: 34), with: .color(.white.opacity(0.36)), lineWidth: 2)
                let saucer = CGRect(x: centerX - 145, y: cupY + 78, width: 290, height: 22)
                context.fill(Path(ellipseIn: saucer), with: .color(.white.opacity(0.14)))
            }
        }
    }
}

private struct ManualSecondsField: View {
    let title: String
    @Binding var seconds: Int
    var textColor: Color = Theme.Colors.textPrimary
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(textColor.opacity(0.78))
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .font(.headline.monospacedDigit())
                .foregroundStyle(textColor)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
                .onAppear { text = String(seconds) }
                .onChange(of: text) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue { text = digits }
                    seconds = min(Int(digits) ?? 0, 900)
                }
                .onChange(of: seconds) { _, newValue in
                    let value = String(newValue)
                    if text != value { text = value }
                }
            Text("s")
                .foregroundStyle(textColor.opacity(0.68))
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
