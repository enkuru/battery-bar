import IOKit

/// How worn the battery is, in the figures System Settings shows under Battery Health.
struct BatteryHealth: Equatable {
    /// The charge the battery holds when full, as a percentage of what it held new.
    let maximumCapacity: Int
    let cycleCount: Int
    /// Nil when the controller does not report the cycles the battery is designed for.
    let designCycleCount: Int?
}

/// The battery controller's own figures from the IORegistry. Apple does not document these keys,
/// so a macOS update may drop them; callers then get nil.
enum BatteryGauge {
    /// The energy left in the battery, in watt-hours.
    static func remainingWattHours() -> Double? {
        withBattery { battery in
            guard let milliampHours = property("AppleRawCurrentCapacity", of: battery),
                  let millivolts = property("Voltage", of: battery)
            else { return nil }
            return Double(milliampHours) * Double(millivolts) / 1_000_000
        }
    }

    /// The energy the battery holds when full, in watt-hours.
    static func fullChargeWattHours() -> Double? {
        withBattery { battery in
            guard let milliampHours = property("AppleRawMaxCapacity", of: battery),
                  let millivolts = property("Voltage", of: battery)
            else { return nil }
            return Double(milliampHours) * Double(millivolts) / 1_000_000
        }
    }

    /// The power going into the battery, in watts; nil while it takes none. The SMC's battery figure stays
    /// near 1 W while charging, so charging comes from the battery's own gauge, which refreshes every minute.
    static func chargingWatts() -> Double? {
        withBattery { battery in
            guard let milliamps = property("Amperage", of: battery), milliamps > 0,
                  let millivolts = property("Voltage", of: battery)
            else { return nil }
            return Double(milliamps) * Double(millivolts) / 1_000_000
        }
    }

    static func health() -> BatteryHealth? {
        withBattery { battery in
            guard let fullCharge = property("NominalChargeCapacity", of: battery)
                    ?? property("AppleRawMaxCapacity", of: battery),
                  let design = property("DesignCapacity", of: battery), design > 0,
                  let cycles = property("CycleCount", of: battery)
            else { return nil }

            // A new battery can hold a little more than its design capacity; System Settings stops at 100%.
            let percentage = Int((Double(fullCharge) / Double(design) * 100).rounded())
            return BatteryHealth(maximumCapacity: min(percentage, 100), cycleCount: cycles,
                                 designCycleCount: property("DesignCycleCount9C", of: battery))
        }
    }

    private static func withBattery<Value>(_ read: (io_registry_entry_t) -> Value?) -> Value? {
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(battery) }

        return read(battery)
    }

    /// Newer Macs keep the capacity figures only inside BatteryData; older ones list them at the top level.
    private static func property(_ key: String, of entry: io_registry_entry_t) -> Int? {
        if let value = copyProperty(key, of: entry) as? Int { return value }
        return (copyProperty("BatteryData", of: entry) as? [String: Any])?[key] as? Int
    }

    private static func copyProperty(_ key: String, of entry: io_registry_entry_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
