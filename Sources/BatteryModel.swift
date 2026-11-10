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

    /// When the Mac last came off the charger, and how full it was then.
    struct Unplug: Codable {
        let date: Date
        let percentage: Int
    }

    nonisolated static let historySpan: TimeInterval = 60
    /// How far the chart's right edge trails the clock while it scrolls, so the next sample arrives before
    /// the edge reaches it.
    nonisolated static let chartLag: TimeInterval = 1.5
    nonisolated static let topAppCount = 3
    private static let liveInterval: TimeInterval = 1
    private static let backgroundInterval: TimeInterval = 2
    private static let backgroundAppScanInterval: TimeInterval = 10
    /// A longer gap between readings means the Mac slept, which says nothing about how it uses power.
    private static let maxLearningGap: TimeInterval = 10
    /// The stretch of readings on the charger whose average seeds the time left once unplugged.
    private static let seedSpan: TimeInterval = 30
    private static let unplugKey = "Unplugged"

    private(set) var state: BatteryState?
    /// Nil until the first reading, and always on Macs whose SMC lacks the power sensors.
    private(set) var reading: PowerReading?
    /// The Mac's power draw over the last minute, oldest first.
    private(set) var history: [Sample] = []
    /// The apps using the most processor power; nil while the first measurement runs.
    private(set) var topApps: [AppPower]?
    /// Read with each battery change, since the cycle count only moves as the charge does.
    private(set) var health: BatteryHealth?
    /// Nil on the charger.
    private(set) var unplug: Unplug?
    /// The percentage the time to full aims at: 100, or where charging has been stopping.
    private(set) var chargeTarget = 100
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
    @ObservationIgnored private var dischargeEstimator = DischargeEstimator(seedWatts: nil, at: .now)
    @ObservationIgnored private var chargeEstimator = ChargeEstimator(seedWatts: nil, at: .now)
    @ObservationIgnored private var learned = LearnedPower.load()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastAppScan: Date?

    /// Until empty on battery, until the charge target while charging: BatteryBar's own estimate once it has
    /// one, else macOS's. Nil on the charger when not charging.
    var timeRemaining: BatteryState.TimeRemaining? {
        guard let state, state.charge == .discharging || state.charge == .charging else { return nil }

        if let ownEstimate { return .estimate(ownEstimate) }
        return state.timeRemaining ?? .calculating
    }

    init() {
        reschedule(sampleNow: true)
    }

    func update(_ newState: BatteryState?) {
        let previous = state
        state = newState
        health = newState == nil ? nil : BatteryGauge.health()

        if let newState {
            if newState.charge != previous?.charge { powerSourceChanged(from: previous, to: newState) }
            // Charging went past where it used to stop, so that limit is gone.
            if newState.charge == .charging, let stop = learned.chargeStop, newState.percentage > stop {
                learned.chargeStop = nil
            }
            learned.save()
        }
        refreshEstimate()
        onChange?()
    }

    /// Starts each estimate afresh, seeded with what BatteryBar already knows, so it is ready at once.
    private func powerSourceChanged(from previous: BatteryState?, to state: BatteryState) {
        let now = Date.now
        switch state.charge {
        case .discharging:
            dischargeEstimator = DischargeEstimator(seedWatts: recentWatts(at: now) ?? learned.drainWatts, at: now)
            // At launch the Mac may have been unplugged for a while already.
            let saved = previous == nil ? Self.savedUnplug(notBelow: state.percentage) : nil
            setUnplug(saved ?? Unplug(date: now, percentage: state.percentage))
        case .charging:
            let learnedWatts = state.percentage < 100 ? learned.chargeWatts[state.percentage] : nil
            chargeEstimator = ChargeEstimator(seedWatts: learnedWatts, at: now)
            setUnplug(nil)
        case .notCharging, .charged:
            setUnplug(nil)
        }

        guard previous?.charge == .charging else { return }
        // A stop below 80% is more likely heat or a weak charger than a charge limit.
        if state.charge == .notCharging, (80..<100).contains(state.percentage) {
            learned.chargeStop = state.percentage
        } else if state.charge == .charged {
            learned.chargeStop = nil
        }
    }

    /// The Mac's average draw over the last half minute, when the readings cover it.
    private func recentWatts(at now: Date) -> Double? {
        let recent = history.filter { now.timeIntervalSince($0.date) <= Self.seedSpan }
        guard let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= Self.seedSpan / 2
        else { return nil }
        return recent.map(\.watts).reduce(0, +) / Double(recent.count)
    }

    private func setUnplug(_ newUnplug: Unplug?) {
        unplug = newUnplug
        UserDefaults.standard.set(newUnplug.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.unplugKey)
    }

    /// The unplug saved before BatteryBar last quit, unless the battery has charged since.
    private static func savedUnplug(notBelow percentage: Int) -> Unplug? {
        guard let data = UserDefaults.standard.data(forKey: unplugKey),
              let saved = try? JSONDecoder().decode(Unplug.self, from: data),
              saved.percentage >= percentage
        else { return nil }
        return saved
    }

    private func refreshEstimate() {
        var estimate: Duration?
        var target = 100

        switch state?.charge {
        case .discharging?:
            if let wattHours = BatteryGauge.remainingWattHours() {
                estimate = dischargeEstimator.timeLeft(remainingWattHours: wattHours)
            }
        case .charging?:
            guard let state, let fullWattHours = BatteryGauge.fullChargeWattHours() else { break }
            let stop = learned.chargeStop.flatMap { $0 > state.percentage ? $0 : nil }
            estimate = chargeEstimator.timeToCharge(from: state.percentage, to: stop ?? 100,
                                                    fullWattHours: fullWattHours, curve: learned.chargeWatts)
            if estimate != nil, let stop { target = stop }
        case .notCharging?, .charged?, nil:
            break
        }
        ownEstimate = estimate
        chargeTarget = target
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
        guard var reading = sensor?.read() else { return }
        if state?.charge == .charging {
            // Zero until the gauge first sees current going in, which the estimators and learning skip.
            reading = PowerReading(system: reading.system, battery: BatteryGauge.chargingWatts() ?? 0,
                                   adapter: reading.adapter)
        }

        let now = Date.now
        let gap = history.last.map { now.timeIntervalSince($0.date) } ?? .infinity
        self.reading = reading
        // One sample older than the chart's window stays, so the line reaches its left edge.
        let windowStart = now.addingTimeInterval(-(Self.historySpan + Self.chartLag))
        if let firstInWindow = history.firstIndex(where: { $0.date >= windowStart }), firstInWindow > 1 {
            history.removeFirst(firstInWindow - 1)
        }
        history.append(Sample(date: now, watts: reading.system))
        // The scan's 15-second limit (AppPowerMeter.maxInterval) leaves room for timer tolerance at 10 seconds.
        if isLive || lastAppScan.map({ now.timeIntervalSince($0) >= Self.backgroundAppScanInterval }) ?? true {
            topApps = appMeter.sample(at: now, top: Self.topAppCount)
            lastAppScan = now
        }

        switch state?.charge {
        case .discharging?:
            dischargeEstimator.add(watts: reading.battery, at: now)
            if gap <= Self.maxLearningGap { learned.learnDrain(watts: reading.battery, over: gap) }
        case .charging?:
            chargeEstimator.add(watts: reading.battery, at: now)
            if let state, gap <= Self.maxLearningGap {
                learned.learnCharge(watts: reading.battery, at: state.percentage, over: gap)
            }
        case .notCharging?, .charged?, nil:
            break
        }
        refreshEstimate()
        onChange?()
    }
}
