import Foundation
import Observation

/// What the menu and the menu bar item show. Power is read every second while the menu is open and every
/// 2 seconds otherwise, so the chart already holds the last minute when the menu opens. The per-app scan
/// costs most, so with the menu closed it runs only every 10 seconds.
@MainActor
@Observable
final class BatteryModel {
    struct Sample {
        let date: Date
        let watts: Double
    }

    nonisolated static let historySpan: TimeInterval = 60
    nonisolated static let topAppCount = 3
    private static let liveInterval: TimeInterval = 1
    private static let backgroundInterval: TimeInterval = 2
    private static let backgroundAppScanInterval: TimeInterval = 10

    private(set) var state: BatteryState?
    /// Nil until the first reading, and always on Macs whose SMC lacks the power sensors.
    private(set) var reading: PowerReading?
    /// The Mac's power draw over the last minute, oldest first.
    private(set) var history: [Sample] = []
    /// The apps using the most processor power; nil while the first measurement runs.
    private(set) var topApps: [AppPower]?
    private var ownEstimate: Duration?

    /// True while the menu is open.
    var isLive = false {
        didSet {
            if isLive != oldValue { reschedule(sampleNow: isLive) }
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let sensor = PowerSensor()
    @ObservationIgnored private let appMeter = AppPowerMeter()
    @ObservationIgnored private var estimator = DischargeEstimator()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastAppScan: Date?

    /// Until empty on battery (BatteryBar's own estimate once it has one, else macOS's), until full while
    /// charging (macOS's), and nil otherwise.
    var timeRemaining: BatteryState.TimeRemaining? {
        guard let state else { return nil }
        guard state.charge == .discharging else { return state.timeRemaining }

        if let ownEstimate { return .estimate(ownEstimate) }
        return state.timeRemaining ?? .calculating
    }

    private var isOnBattery: Bool { state?.charge == .discharging }

    init() {
        reschedule(sampleNow: true)
    }

    func update(_ newState: BatteryState?) {
        let wasOnBattery = isOnBattery
        state = newState

        if isOnBattery != wasOnBattery {
            estimator = DischargeEstimator()
            ownEstimate = nil
        }
        onChange?()
    }

    private func reschedule(sampleNow: Bool) {
        timer?.invalidate()
        timer = nil
        guard sensor != nil else { return }

        let interval = isLive ? Self.liveInterval : Self.backgroundInterval
        if sampleNow { sample() }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = interval / 5
        // Common modes, because an open menu runs the run loop in event-tracking mode.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reads power once; the menu calls it before opening, so it never shows stale figures.
    func sample() {
        guard let reading = sensor?.read() else { return }

        let now = Date.now
        self.reading = reading
        // One sample older than the span stays, so the chart's line reaches its left edge.
        if let firstInSpan = history.firstIndex(where: { now.timeIntervalSince($0.date) <= Self.historySpan }), firstInSpan > 1 {
            history.removeFirst(firstInSpan - 1)
        }
        history.append(Sample(date: now, watts: reading.system))
        // The scan's 15-second limit (AppPowerMeter.maxInterval) leaves room for timer tolerance at 10 seconds.
        if isLive || lastAppScan.map({ now.timeIntervalSince($0) >= Self.backgroundAppScanInterval }) ?? true {
            topApps = appMeter.sample(at: now, top: Self.topAppCount)
            lastAppScan = now
        }

        if isOnBattery {
            estimator.add(watts: reading.battery, at: now)
            if let wattHours = BatteryGauge.remainingWattHours(),
               let estimate = estimator.timeLeft(remainingWattHours: wattHours) {
                ownEstimate = estimate
            }
        }
        onChange?()
    }
}
