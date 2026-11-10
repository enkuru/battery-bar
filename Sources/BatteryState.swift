import Foundation
import IOKit.ps

struct BatteryState: Equatable {
    enum Charge: Equatable {
        case discharging
        case charging
        case notCharging
        case charged
    }

    enum TimeRemaining: Equatable {
        case calculating
        case estimate(Duration)
    }

    struct Adapter: Equatable {
        /// Nil when the charger does not report a name.
        let name: String?
        /// The most the charger agreed to deliver to this Mac, which can be less than its rating.
        let watts: Int
    }

    let percentage: Int
    let charge: Charge
    let isLowPowerMode: Bool
    /// macOS's estimate until empty while discharging, or until full while charging; nil otherwise.
    let timeRemaining: TimeRemaining?
    /// Nil on battery, and for chargers that do not report their power.
    let adapter: Adapter?
    /// macOS's own verdict that the battery should be serviced.
    let needsService: Bool

    var isOnPowerAdapter: Bool { charge != .discharging }

    /// Reads the internal battery; nil on Macs without one.
    static func current() -> BatteryState? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maxCapacity = description[kIOPSMaxCapacityKey] as? Int, maxCapacity > 0
            else { continue }

            let percentage = Int((Double(capacity) / Double(maxCapacity) * 100).rounded())
            let charge = charge(from: description)
            return BatteryState(percentage: min(percentage, 100),
                                charge: charge,
                                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                timeRemaining: timeRemaining(from: description, charge: charge),
                                adapter: charge == .discharging ? nil : adapter(),
                                needsService: needsService(from: description))
        }
        return nil
    }

    private static func adapter() -> Adapter? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = details[kIOPSPowerAdapterWattsKey] as? Int
        else { return nil }
        // "Name" is not among IOKit's documented keys, so it may be missing.
        return Adapter(name: details["Name"] as? String, watts: watts)
    }

    /// Either key marks a battery macOS wants serviced; a healthy battery may publish neither.
    private static func needsService(from description: [String: Any]) -> Bool {
        if description[kIOPSBatteryHealthConditionKey] != nil { return true }
        return (description[kIOPSBatteryHealthKey] as? String).map { $0 != kIOPSGoodValue } ?? false
    }

    private static func timeRemaining(from description: [String: Any], charge: Charge) -> TimeRemaining? {
        let key: String
        switch charge {
        case .discharging: key = kIOPSTimeToEmptyKey
        case .charging: key = kIOPSTimeToFullChargeKey
        case .notCharging, .charged: return nil
        }

        // IOKit reports minutes, and -1 while it is still measuring after a power change.
        guard let minutes = description[key] as? Int else { return nil }
        return minutes < 0 ? .calculating : .estimate(.seconds(minutes * 60))
    }

    private static func charge(from description: [String: Any]) -> Charge {
        guard description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue else { return .discharging }

        if description[kIOPSIsChargedKey] as? Bool == true { return .charged }
        return description[kIOPSIsChargingKey] as? Bool == true ? .charging : .notCharging
    }
}
