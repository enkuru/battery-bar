import IOKit

/// The battery controller's own figures from the IORegistry. Apple does not document these keys,
/// so a macOS update may drop them; callers then get nil.
enum BatteryGauge {
    /// The energy left in the battery, in watt-hours.
    static func remainingWattHours() -> Double? {
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(battery) }

        guard let milliampHours = property("AppleRawCurrentCapacity", of: battery),
              let millivolts = property("Voltage", of: battery)
        else { return nil }
        return Double(milliampHours) * Double(millivolts) / 1_000_000
    }

    private static func property(_ key: String, of entry: io_registry_entry_t) -> Int? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }
}
