import SwiftUI

/// The top of the menu: the charge, the time left in words, and live power use.
struct MenuPanel: View {
    static let width: CGFloat = 300

    let model: BatteryModel
    let quit: @MainActor (NSRunningApplication) -> Void

    var body: some View {
        if let state = model.state {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Header(state: state)
                    Summary(state: state, timeRemaining: model.timeRemaining, chargeTarget: model.chargeTarget,
                            unplug: model.unplug)
                        .padding(.top, 16)
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))

                if let reading = model.reading {
                    Divider()
                        .padding(.horizontal, 16)
                    PowerSection(state: state, reading: reading, history: model.history, isLive: model.isLive)
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
                    Divider()
                        .padding(.horizontal, 16)
                    TopApps(apps: model.topApps, quit: quit)
                        // A closing menu may never report the pointer leaving, so each opening starts fresh.
                        .id(model.isLive)
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
                }

                if let health = model.health {
                    Divider()
                        .padding(.horizontal, 16)
                    HealthSection(health: health, needsService: state.needsService)
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
                }
            }
            .frame(width: Self.width, alignment: .leading)
        }
    }
}

private struct Header: View {
    let state: BatteryState

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: BatteryIcon.image(for: state, scale: 1.7,
                                             appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)))
                .foregroundStyle(.primary)
                .accessibilityLabel("Battery \(state.percentage)%")
            Spacer()
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        switch state.charge {
        case .discharging: "On battery"
        case .charging: "Charging"
        case .notCharging, .charged: "Plugged in"
        }
    }
}

/// The time left in words, with the clock time it ends.
private struct Summary: View {
    let state: BatteryState
    let timeRemaining: BatteryState.TimeRemaining?
    let chargeTarget: Int
    let unplug: BatteryModel.Unplug?

    private static let numberFont = Font.system(size: 32, weight: .semibold)
    private static let wordFont = Font.system(size: 17, weight: .medium)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            headline
                .foregroundStyle(BatteryTone(state) == .low ? Color(nsColor: BatteryTone.low.ink) : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(RollingNumber(value: estimate))
            ForEach([detail, sinceUnplug].compactMap { $0 }, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "On battery for 1h 20m, 35% used"; nil on the charger and in the first minute.
    private var sinceUnplug: String? {
        guard state.charge == .discharging, let unplug else { return nil }

        let elapsed = Date.now.timeIntervalSince(unplug.date)
        guard elapsed >= 60 else { return nil }
        let time = TimeLeftFormat.compact(.seconds(elapsed))
        let used = unplug.percentage - state.percentage
        return used > 0 ? "On battery for \(time), \(used)% used" : "On battery for \(time)"
    }

    private var chargeSuffix: String {
        chargeTarget == 100 ? "to full" : "to \(chargeTarget)%"
    }

    private var estimate: Duration? {
        if case .estimate(let duration) = timeRemaining { return duration }
        return nil
    }

    private var headline: Text {
        switch (state.charge, estimate) {
        case (.discharging, let duration?): spelled(duration, then: "left")
        case (.charging, let duration?): spelled(duration, then: chargeSuffix)
        case (.discharging, nil): title("Estimating time left")
        case (.charging, nil): title("Charging")
        case (.notCharging, _): title("Not charging")
        case (.charged, _): title("Fully charged")
        }
    }

    private var detail: String {
        switch (state.charge, estimate) {
        case (.discharging, let duration?): "Runs out around \(TimeLeftFormat.clockTime(after: duration))"
        case (.charging, let duration?) where chargeTarget == 100:
            "Full around \(TimeLeftFormat.clockTime(after: duration))"
        case (.charging, let duration?):
            "Reaches \(chargeTarget)% around \(TimeLeftFormat.clockTime(after: duration))"
        case (.discharging, nil): "Ready in a few seconds."
        case (.charging, nil): "Working out the time to full."
        case (.notCharging, _): "Your Mac runs on the charger. The battery stays at \(state.percentage)%."
        case (.charged, _): "Your Mac runs on the charger."
        }
    }

    /// "2 hours 55 minutes left", with the numbers set larger than the words.
    private func spelled(_ duration: Duration, then suffix: String) -> Text {
        let parts = TimeLeftFormat.parts(duration).map { part in
            Text("\(Text(verbatim: String(part.value)).font(Self.numberFont)) \(Text(verbatim: part.unit).font(Self.wordFont))")
        }
        let time = parts.dropFirst().reduce(parts[0]) { text, part in Text("\(text)  \(part)") }
        return Text("\(time) \(Text(verbatim: suffix).font(Self.wordFont))")
            .monospacedDigit()
    }

    private func title(_ text: String) -> Text {
        Text(text).font(.system(size: 26, weight: .semibold))
    }
}

private struct PowerSection: View {
    let state: BatteryState
    let reading: PowerReading
    let history: [BatteryModel.Sample]
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Using now")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Watts.text(reading.system))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .modifier(RollingNumber(value: reading.system))
            }
            PowerChart(samples: history, tone: BatteryTone(state), isLive: isLive)
                .frame(height: 40)
                .padding(.top, 8)
                .accessibilityLabel("Power use over the last minute")
            HStack {
                Text("1 min ago")
                Spacer()
                Text("Now")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            PowerFlow(state: state, reading: reading)
                .padding(.top, 14)
            if let adapter = state.adapter {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(adapter.name ?? "Power adapter")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text("up to \(adapter.watts) W")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
                .padding(.top, 12)
            }
        }
    }
}

/// The last minute of power draw, newest at the right. While the menu is open the line scrolls with the clock
/// and the scale eases to each new peak, instead of both jumping once a second.
private struct PowerChart: View {
    let samples: [BatteryModel.Sample]
    let tone: BatteryTone
    let isLive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let minimumScale = 10.0
    /// The line moves about 5 points a second, so 30 frames a second already looks smooth.
    private static let frameInterval = 1.0 / 30

    var body: some View {
        let animates = isLive && !reduceMotion
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !animates)) { timeline in
            // A paused timeline keeps the date it paused at, so without animation the chart reads the clock.
            PowerPlot(samples: samples, tone: tone, top: scale,
                      end: (animates ? timeline.date : .now).addingTimeInterval(-BatteryModel.chartLag))
        }
        .animation(animates ? .easeInOut(duration: 0.6) : nil, value: scale)
    }

    private var scale: Double {
        max(Self.minimumScale, (samples.map(\.watts).max() ?? 0) * 1.25)
    }
}

/// One frame of the chart; SwiftUI animates its scale.
private struct PowerPlot: View, Animatable {
    let samples: [BatteryModel.Sample]
    let tone: BatteryTone
    var top: Double
    /// The time at the right edge.
    let end: Date

    /// A longer gap means sampling paused (menu closed on the charger), so the line breaks there.
    private static let maxGap: TimeInterval = 7

    nonisolated var animatableData: Double {
        get { top }
        set { top = newValue }
    }

    var body: some View {
        let color = Color(nsColor: tone.ink)
        Canvas { context, size in
            // The newest sample lies past the right edge until the clock catches up with it.
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            func point(_ sample: BatteryModel.Sample) -> CGPoint {
                CGPoint(x: size.width * (1 - end.timeIntervalSince(sample.date) / BatteryModel.historySpan),
                        y: size.height - 2 - (size.height - 4) * min(sample.watts / top, 1))
            }

            for run in runs() where run.count > 1 {
                let points = run.map(point)
                var line = Path()
                line.addLines(points)

                var area = line
                area.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                area.addLine(to: CGPoint(x: points[0].x, y: size.height))
                area.closeSubpath()

                context.fill(area, with: .color(color.opacity(tone == .plain ? 0.12 : 0.2)))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func runs() -> [[BatteryModel.Sample]] {
        var runs: [[BatteryModel.Sample]] = []
        for sample in samples {
            if let last = runs.last?.last, sample.date.timeIntervalSince(last.date) <= Self.maxGap {
                runs[runs.count - 1].append(sample)
            } else {
                runs.append([sample])
            }
        }
        return runs
    }
}

/// Where the power goes: charger to Mac, and battery to Mac or charger to battery.
private struct PowerFlow: View {
    let state: BatteryState
    let reading: PowerReading

    private static let dimmed = 0.25

    var body: some View {
        HStack(spacing: 0) {
            Node(symbol: "powerplug", value: charger, label: "Charger", isIdle: !state.isOnPowerAdapter)
            Arrow(pointsRight: true, isActive: state.isOnPowerAdapter)
            Node(symbol: "laptopcomputer", value: Watts.text(reading.system), label: "Mac", isIdle: false)
            Arrow(pointsRight: state.charge == .charging, isActive: batteryIsActive)
            Node(symbol: "battery.75percent", value: battery, label: "Battery", isIdle: !batteryIsActive)
        }
    }

    private var batteryIsActive: Bool { state.charge == .discharging || state.charge == .charging }

    private var charger: String {
        state.isOnPowerAdapter ? Watts.text(reading.adapter) : "Unplugged"
    }

    private var battery: String {
        switch state.charge {
        case .discharging: Watts.text(reading.battery)
        case .charging: "+" + Watts.text(reading.battery)
        case .notCharging, .charged: "Resting"
        }
    }

    private struct Node: View {
        let symbol: String
        let value: String
        let label: String
        let isIdle: Bool

        var body: some View {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(height: 16)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .modifier(RollingNumber(value: value))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isIdle ? .secondary : .primary)
            .frame(maxWidth: .infinity)
        }
    }

    private struct Arrow: View {
        let pointsRight: Bool
        let isActive: Bool

        var body: some View {
            Image(systemName: pointsRight ? "arrow.right" : "arrow.left")
                .font(.system(size: 11, weight: .medium))
                .opacity(isActive ? 1 : PowerFlow.dimmed)
                .frame(width: 24)
                .accessibilityHidden(true)
        }
    }
}

/// The apps drawing the most processor power, to show what to quit for a longer battery life.
private struct TopApps: View {
    let apps: [AppPower]?
    let quit: @MainActor (NSRunningApplication) -> Void

    /// The list as it was when the pointer arrived, so rows don't swap places under a Quit button.
    @State private var heldApps: [AppPower]?

    static let rowHeight: CGFloat = 22
    private static let rowSpacing: CGFloat = 4
    /// Room for every row, so the menu keeps its height as apps come and go.
    private static let listHeight = CGFloat(BatteryModel.topAppCount) * rowHeight
        + CGFloat(BatteryModel.topAppCount - 1) * rowSpacing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps using the most power")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                if let shown = heldApps ?? apps, !shown.isEmpty {
                    ForEach(shown) { app in
                        AppRow(app: app, quit: quit)
                    }
                } else {
                    Text(apps == nil ? "Measuring…" : "No app is using much power.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(height: Self.rowHeight)
                }
            }
            .frame(height: Self.listHeight, alignment: .top)
            .onHover { isInside in heldApps = isInside ? apps : nil }
            Text("Processor power only, not the screen or graphics.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One app, with a Quit button while the pointer is on it.
private struct AppRow: View {
    let app: AppPower
    let quit: @MainActor (NSRunningApplication) -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(app.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(Watts.text(app.watts))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if isHovered, let runningApp = app.runningApp {
                Button("Quit") { quit(runningApp) }
                    .buttonStyle(QuitButtonStyle())
                    .accessibilityLabel("Quit \(app.name)")
            }
        }
        .font(.system(size: 13))
        .frame(height: TopApps.rowHeight)
        .padding(.horizontal, 6)
        .background(isHovered && app.runningApp != nil ? highlight : .clear, in: .rect(cornerRadius: 6))
        .padding(.horizontal, -6)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if let runningApp = app.runningApp {
                Button("Quit \(app.name)") { quit(runningApp) }
            }
        }
    }

    private var highlight: Color {
        colorScheme == .dark ? .white.opacity(0.09) : .black.opacity(0.06)
    }

    private struct QuitButtonStyle: ButtonStyle {
        @Environment(\.colorScheme) private var colorScheme

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(fill(isPressed: configuration.isPressed), in: .rect(cornerRadius: 5))
        }

        private func fill(isPressed: Bool) -> Color {
            colorScheme == .dark
                ? .white.opacity(isPressed ? 0.28 : 0.18)
                : .black.opacity(isPressed ? 0.16 : 0.09)
        }
    }
}

/// How worn the battery is, in System Settings' terms.
private struct HealthSection: View {
    let health: BatteryHealth
    let needsService: Bool

    private static let warning = Color(nsColor: .adaptive(light: 0xC93400, dark: 0xFF9F0A))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Battery health")
                .font(.system(size: 13, weight: .semibold))
            VStack(spacing: 2) {
                row("Maximum capacity", value: Text(verbatim: "\(health.maximumCapacity)%"))
                row("Charge cycles", value: Text(verbatim: cycles))
                row("Condition", value: needsService
                    ? Text("Service recommended").fontWeight(.semibold).foregroundStyle(Self.warning)
                    : Text("Normal"))
            }
            .padding(.top, 8)
            if needsService {
                Text("The battery holds less charge than when it was new.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    private var cycles: String {
        guard let design = health.designCycleCount else { return health.cycleCount.formatted() }
        return "\(health.cycleCount.formatted()) of \(design.formatted())"
    }

    private func row(_ label: String, value: Text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            value
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .frame(height: 20)
    }
}

/// Digits that roll to a new value instead of jumping; a plain swap with Reduce Motion on.
private struct RollingNumber<Value: Equatable>: ViewModifier {
    let value: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: value)
    }
}

private enum Watts {
    static func text(_ watts: Double) -> String {
        watts.formatted(.number.precision(.fractionLength(1))) + " W"
    }
}
