import AppKit

/// The color a battery state is shown in, shared by the menu bar icon and the menu:
/// yellow in Low Power Mode, green on the charger, red when low on battery, plain otherwise.
enum BatteryTone {
    case plain
    case powered
    case low
    case lowPower

    private static let lowBatteryThreshold = 20

    init(_ state: BatteryState) {
        if state.isLowPowerMode {
            self = .lowPower
        } else if state.isOnPowerAdapter {
            self = .powered
        } else if state.percentage <= Self.lowBatteryThreshold {
            self = .low
        } else {
            self = .plain
        }
    }

    /// The battery's fill; nil when plain, so the icon follows the menu bar's black or white.
    var fill: NSColor? {
        switch self {
        case .plain: nil
        case .powered: .systemGreen
        case .low: .systemRed
        case .lowPower: .systemYellow
        }
    }

    /// The same hue, dark enough in light mode to read as text and lines on the menu.
    var ink: NSColor {
        switch self {
        case .plain: .labelColor
        case .powered: .adaptive(light: 0x248A3D, dark: 0x30D158)
        case .low: .adaptive(light: 0xD70015, dark: 0xFF6961)
        case .lowPower: .adaptive(light: 0x9A6B00, dark: 0xFFD60A)
        }
    }
}

extension NSColor {
    static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }

    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
