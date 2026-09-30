import Foundation

/// How long a file is allowed to stay in the watched folder before it goes to the Trash.
public struct ShelfDuration: Hashable, Codable, Sendable, Identifiable {
    public let seconds: TimeInterval

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public var id: TimeInterval { seconds }

    public static func seconds(_ value: Double) -> ShelfDuration { ShelfDuration(seconds: value) }
    public static func minutes(_ value: Double) -> ShelfDuration { ShelfDuration(seconds: value * 60) }
    public static func hours(_ value: Double) -> ShelfDuration { ShelfDuration(seconds: value * 3_600) }
    public static func days(_ value: Double) -> ShelfDuration { ShelfDuration(seconds: value * 86_400) }

    /// The stops offered when a new download arrives.
    public static let standardStops: [ShelfDuration] = [.minutes(10), .minutes(30), .hours(1), .days(1), .days(7), .days(30)]

    /// Stops offered for the onboarding sample, so the whole loop can be watched in seconds.
    public static let demoStops: [ShelfDuration] = [.seconds(30), .minutes(10), .hours(1), .days(1), .days(7), .days(30)]

    public static let defaultDuration: ShelfDuration = .days(1)

    /// Compact label used under the slider stops: "30s", "10m", "1h", "1d", "1w", "30d".
    public var shortLabel: String {
        let s = Int(seconds.rounded())
        switch s {
        case ..<60: return "\(s)s"
        case ..<3_600: return "\(s / 60)m"
        case ..<86_400: return "\(s / 3_600)h"
        default:
            let days = s / 86_400
            if days % 7 == 0 && days < 28 { return "\(days / 7)w" }
            return "\(days)d"
        }
    }

    /// Spelled-out label: "30 seconds", "10 minutes", "1 hour", "1 day", "1 week", "30 days".
    public var longLabel: String {
        let s = Int(seconds.rounded())
        func plural(_ n: Int, _ unit: String) -> String { n == 1 ? "1 \(unit)" : "\(n) \(unit)s" }
        switch s {
        case ..<60: return plural(s, "second")
        case ..<3_600: return plural(s / 60, "minute")
        case ..<86_400: return plural(s / 3_600, "hour")
        default:
            let days = s / 86_400
            if days % 7 == 0 && days < 28 { return plural(days / 7, "week") }
            return plural(days, "day")
        }
    }

    /// Index of the stop closest to `duration`, compared on a log scale so that
    /// "20 hours" snaps to "1 day" rather than to "1 hour".
    public static func nearestIndex(to duration: TimeInterval, in stops: [ShelfDuration]) -> Int {
        guard !stops.isEmpty else { return 0 }
        let target = log(max(duration, 1))
        return stops.indices.min { lhs, rhs in
            abs(log(stops[lhs].seconds) - target) < abs(log(stops[rhs].seconds) - target)
        } ?? 0
    }
}
