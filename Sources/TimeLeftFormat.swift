import Foundation

/// How BatteryBar words a time estimate. Above an hour it rounds to 5 minutes, so the number does not
/// flicker with every small change in power use.
enum TimeLeftFormat {
    struct Part: Equatable {
        let value: Int
        let unit: String
    }

    /// "2 hours", "55 minutes": the menu sets numbers and words in different sizes.
    static func parts(_ duration: Duration) -> [Part] {
        let (hours, minutes) = hoursAndMinutes(duration)
        var parts: [Part] = []
        if hours > 0 { parts.append(Part(value: hours, unit: hours == 1 ? "hour" : "hours")) }
        if minutes > 0 || hours == 0 { parts.append(Part(value: minutes, unit: minutes == 1 ? "minute" : "minutes")) }
        return parts
    }

    /// "2h 55m", short enough to sit under the menu bar icon.
    static func compact(_ duration: Duration) -> String {
        let (hours, minutes) = hoursAndMinutes(duration)
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// The clock time the estimate ends, to the nearest 5 minutes: "13:05", or "1:05 PM" on a 12-hour clock.
    static func clockTime(after duration: Duration, from now: Date = .now) -> String {
        let end = now.addingTimeInterval(Double(duration.components.seconds))
        let rounded = Date(timeIntervalSinceReferenceDate: (end.timeIntervalSinceReferenceDate / 300).rounded() * 300)
        return rounded.formatted(date: .omitted, time: .shortened)
    }

    private static func hoursAndMinutes(_ duration: Duration) -> (hours: Int, minutes: Int) {
        var minutes = max(1, Int((Double(duration.components.seconds) / 60).rounded()))
        if minutes >= 60 { minutes = Int((Double(minutes) / 5).rounded()) * 5 }
        return (minutes / 60, minutes % 60)
    }
}
