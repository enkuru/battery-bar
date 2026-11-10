import Foundation

/// Time left on battery: the energy left divided by recent power use. With a seed (what the Mac drew on the
/// charger just before, or its learned typical drain) the estimate is ready the moment it is unplugged;
/// without one, about ten seconds later. macOS waits several minutes for its own. The power is averaged over
/// about two minutes, so a short burst does not swing the number.
struct DischargeEstimator {
    private static let smoothing: TimeInterval = 120
    private static let warmUp: TimeInterval = 10

    private var averageWatts = 0.0
    private var sampleCount = 0
    private var firstSample: Date?
    private var lastSample: Date?
    private var isSeeded = false

    init(seedWatts: Double?, at date: Date) {
        guard let seedWatts, seedWatts > 0 else { return }
        averageWatts = seedWatts
        isSeeded = true
        firstSample = date
        lastSample = date
    }

    mutating func add(watts: Double, at date: Date) {
        guard watts > 0 else { return }

        if let lastSample {
            sampleCount += 1
            // Unseeded, a plain mean while there are few samples, so the first one cannot dominate; then an
            // average weighted by elapsed time, so samples every second and every 2 seconds count alike.
            let decay = 1 - exp(-date.timeIntervalSince(lastSample) / Self.smoothing)
            let weight = isSeeded ? decay : max(1 / Double(sampleCount), decay)
            averageWatts += weight * (watts - averageWatts)
        } else {
            averageWatts = watts
            sampleCount = 1
            firstSample = date
        }
        lastSample = date
    }

    /// Nil until the samples span the warm-up time, unless seeded.
    func timeLeft(remainingWattHours: Double) -> Duration? {
        guard let firstSample, let lastSample, averageWatts > 0,
              isSeeded || lastSample.timeIntervalSince(firstSample) >= Self.warmUp
        else { return nil }
        return .seconds(remainingWattHours / averageWatts * 3600)
    }
}
