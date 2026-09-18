import Foundation

public enum TimeFormat {
    /// Largest value formatted as-is; keeps the Double → Int conversion safe for absurd inputs.
    private static let largestFormatted: TimeInterval = 1_000_000_000

    /// Countdown text: "24:59", "1:02:03". Rounds up to whole seconds; negative shows "0:00".
    /// Non-finite values show "0:00". A millisecond of slack absorbs floating-point noise from Date
    /// arithmetic, so a phase that just started at 25 minutes shows "25:00", not "25:01".
    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(min((seconds - 0.001).rounded(.up), largestFormatted))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        return hours > 0
            ? "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
            : "\(minutes):\(twoDigits(secs))"
    }

    /// Friendly duration: "45 sec", "25 min", "1 h", "1 h 30 min".
    /// Under a minute it counts whole seconds; otherwise it rounds to the nearest minute.
    /// Negative and non-finite values show "0 sec".
    public static func humanDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 sec" }
        let clamped = min(seconds, largestFormatted)
        let wholeSeconds = Int(clamped.rounded())
        if wholeSeconds < 60 { return "\(wholeSeconds) sec" }
        let totalMinutes = Int((clamped / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(minutes) min"
        }
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
