import Foundation

/// Time left on battery: the energy left divided by recent power use. The first estimate is ready about
/// ten seconds after unplugging, where macOS waits several minutes for its own; after that the power is
/// averaged over about two minutes, so a short burst does not swing the number.
struct DischargeEstimator {
    private static let smoothing: TimeInterval = 120
    private static let warmUp: TimeInterval = 10

    private var averageWatts = 0.0
    private var sampleCount = 0
    private var firstSample: Date?
    private var lastSample: Date?

    mutating func add(watts: Double, at date: Date) {
        guard watts > 0 else { return }

        if let lastSample {
            sampleCount += 1
            // A plain mean while there are few samples, so the first one cannot dominate; then an average
            // weighted by elapsed time, so samples every second and every 2 seconds count alike.
            let weight = max(1 / Double(sampleCount), 1 - exp(-date.timeIntervalSince(lastSample) / Self.smoothing))
            averageWatts += weight * (watts - averageWatts)
        } else {
            averageWatts = watts
            sampleCount = 1
            firstSample = date
        }
        lastSample = date
    }

    /// Nil until the samples span the warm-up time.
    func timeLeft(remainingWattHours: Double) -> Duration? {
        guard let firstSample, let lastSample, lastSample.timeIntervalSince(firstSample) >= Self.warmUp else { return nil }
        return .seconds(remainingWattHours / averageWatts * 3600)
    }
}
