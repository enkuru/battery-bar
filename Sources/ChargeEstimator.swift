import Foundation

/// Time to a charge target: the energy still to go, spread over the percentages left, each at the charging
/// power learned for it and scaled to how fast the battery is taking charge right now. macOS waits minutes
/// after plugging in before it gives its own figure.
struct ChargeEstimator {
    private static let smoothing: TimeInterval = 30

    private var averageWatts: Double?
    private var lastSample: Date?

    /// With a seed (the power learned at this percentage) the first estimate is ready before any reading.
    init(seedWatts: Double?, at date: Date) {
        guard let seedWatts, seedWatts > 0 else { return }
        averageWatts = seedWatts
        lastSample = date
    }

    mutating func add(watts: Double, at date: Date) {
        guard watts > 0 else { return }

        if let averageWatts, let lastSample {
            let weight = 1 - exp(-date.timeIntervalSince(lastSample) / Self.smoothing)
            self.averageWatts = averageWatts + weight * (watts - averageWatts)
        } else {
            averageWatts = watts
        }
        lastSample = date
    }

    /// Nil until there is a reading or a learned power to go on.
    func timeToCharge(from percentage: Int, to target: Int, fullWattHours: Double, curve: [Double?]) -> Duration? {
        guard let live = averageWatts, (0..<target).contains(percentage), curve.indices.contains(target - 1)
        else { return nil }

        let wattHoursPerPercent = fullWattHours / 100
        let hours = (percentage..<target).reduce(0.0) { total, step in
            total + wattHoursPerPercent / Self.watts(at: step, from: percentage, live: live, curve: curve)
        }
        return .seconds(hours * 3600)
    }

    private static func watts(at step: Int, from percentage: Int, live: Double, curve: [Double?]) -> Double {
        if let learned = curve[step], let here = curve[percentage] { return learned * live / here }
        return live * taper(step) / taper(percentage)
    }

    /// A rough charging shape for percentages BatteryBar has not yet seen charge: full power to 80%, then
    /// slower as the battery fills. Learned figures replace it after one charge.
    private static func taper(_ percentage: Int) -> Double {
        percentage < 80 ? 1 : max(0.2, 1 - Double(percentage - 80) * 0.04)
    }
}
