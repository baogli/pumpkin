import Foundation

/// Human-readable time and size strings. The UI is English, so month and weekday
/// names use English with the user's region; clock times follow the user's own
/// 12/24-hour preference.
public enum Formatting {
    /// English, but with the user's regional conventions (date order, first weekday).
    public static var textLocale: Locale {
        Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))
    }

    /// Compact countdown, e.g. "42s", "12m", "5h", "3d".
    public static func compactRemaining(_ interval: TimeInterval) -> String {
        let t = max(0, interval)
        if t < 60 {
            return "\(Int(t.rounded(.up)))s"
        }
        if t < 3_600 {
            let minutes = Int((t / 60).rounded(.up))
            return minutes >= 60 ? "1h" : "\(minutes)m"
        }
        if t < 86_400 {
            let hours = max(1, Int((t / 3_600).rounded()))
            return hours >= 24 ? "1d" : "\(hours)h"
        }
        return "\(max(1, Int((t / 86_400).rounded())))d"
    }

    /// "Today 14:05", "Tomorrow 09:00", "Friday 14:05", "Oct 12, 14:05".
    public static func expiryLabel(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        timeLocale: Locale = .current,
        textLocale: Locale = Formatting.textLocale
    ) -> String {
        let time = formatter("jmm", calendar: calendar, locale: timeLocale).string(from: date)
        let dayDelta = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        switch dayDelta {
        case 0:
            return "Today \(time)"
        case 1:
            return "Tomorrow \(time)"
        case -1:
            return "Yesterday \(time)"
        case 2..<7:
            let weekday = formatter("EEEE", calendar: calendar, locale: textLocale).string(from: date)
            return "\(weekday) \(time)"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let day = formatter(sameYear ? "MMMd" : "yMMMd", calendar: calendar, locale: textLocale).string(from: date)
            return "\(day), \(time)"
        }
    }

    /// "Just now", "5 minutes ago", "Yesterday".
    public static func agoLabel(for date: Date, now: Date = Date(), locale: Locale = Formatting.textLocale) -> String {
        if now.timeIntervalSince(date) < 60 {
            return "Just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let text = formatter.localizedString(for: date, relativeTo: now)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "2.5 MB", "812 KB", "Zero KB".
    public static func size(_ bytes: Int64, locale: Locale = Formatting.textLocale) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[key] = formatter
        return formatter
    }
}
