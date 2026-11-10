import Foundation

/// What BatteryBar has learned about this Mac's power use. It is kept across launches, so a time estimate is
/// ready the moment the power source changes instead of after minutes of measuring.
struct LearnedPower: Codable {
    /// The battery's typical drain, averaged over about half an hour of use.
    var drainWatts: Double?
    /// The charging power last seen at each percentage, 0 to 99. Batteries take charge more slowly as they
    /// fill, so this curve is what keeps time to full right near the top.
    var chargeWatts: [Double?] = Array(repeating: nil, count: 100)
    /// Where charging last stopped short of full with the charger still in: a charge limit, or Optimized
    /// Battery Charging holding at 80%.
    var chargeStop: Int?

    private static let defaultsKey = "LearnedPower"
    private static let drainSmoothing: TimeInterval = 30 * 60
    private static let chargeSmoothing: TimeInterval = 60

    static func load() -> LearnedPower {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let learned = try? JSONDecoder().decode(LearnedPower.self, from: data),
              learned.chargeWatts.count == 100
        else { return LearnedPower() }
        return learned
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    mutating func learnDrain(watts: Double, over interval: TimeInterval) {
        drainWatts = Self.blend(drainWatts, with: watts, over: interval, smoothing: Self.drainSmoothing)
    }

    mutating func learnCharge(watts: Double, at percentage: Int, over interval: TimeInterval) {
        guard chargeWatts.indices.contains(percentage) else { return }
        chargeWatts[percentage] = Self.blend(chargeWatts[percentage], with: watts, over: interval,
                                             smoothing: Self.chargeSmoothing)
    }

    private static func blend(_ average: Double?, with watts: Double, over interval: TimeInterval,
                              smoothing: TimeInterval) -> Double? {
        guard watts > 0 else { return average }
        guard let average else { return watts }
        return average + (1 - exp(-interval / smoothing)) * (watts - average)
    }
}
