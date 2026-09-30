import Foundation
import Testing
@testable import PumpkinCore

@Suite struct ShelfDurationTests {
    @Test func standardStopLabels() {
        #expect(ShelfDuration.standardStops.map(\.shortLabel) == ["10m", "30m", "1h", "1d", "1w", "30d"])
        #expect(ShelfDuration.standardStops.map(\.longLabel) == ["10 minutes", "30 minutes", "1 hour", "1 day", "1 week", "30 days"])
    }

    @Test func demoStopsStartWithSeconds() {
        #expect(ShelfDuration.demoStops.first?.shortLabel == "30s")
        #expect(ShelfDuration.demoStops.first?.longLabel == "30 seconds")
    }

    @Test func pluralisation() {
        #expect(ShelfDuration.seconds(1).longLabel == "1 second")
        #expect(ShelfDuration.hours(2).longLabel == "2 hours")
        #expect(ShelfDuration.days(14).longLabel == "2 weeks")
        #expect(ShelfDuration.days(14).shortLabel == "2w")
        #expect(ShelfDuration.days(3).shortLabel == "3d")
    }

    @Test func nearestIndexSnapsOnLogScale() {
        let stops = ShelfDuration.standardStops
        #expect(ShelfDuration.nearestIndex(to: 86_400, in: stops) == 3)
        #expect(ShelfDuration.nearestIndex(to: 20 * 3_600, in: stops) == 3)
        #expect(ShelfDuration.nearestIndex(to: 45 * 60, in: stops) == 2)
        #expect(ShelfDuration.nearestIndex(to: 1, in: stops) == 0)
        #expect(ShelfDuration.nearestIndex(to: 365 * 86_400, in: stops) == 5)
        #expect(ShelfDuration.nearestIndex(to: 60, in: []) == 0)
    }
}

@Suite struct FormattingTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    let en24 = Locale(identifier: "en_GB")
    let enUS = Locale(identifier: "en_US")

    /// Tuesday 29 September 2026, 12:00 UTC.
    var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 12))!
    }

    func label(_ offset: TimeInterval) -> String {
        Formatting.expiryLabel(for: now.addingTimeInterval(offset), now: now, calendar: calendar, timeLocale: en24, textLocale: enUS)
    }

    @Test func compactRemaining() {
        #expect(Formatting.compactRemaining(-5) == "0s")
        #expect(Formatting.compactRemaining(0) == "0s")
        #expect(Formatting.compactRemaining(0.2) == "1s")
        #expect(Formatting.compactRemaining(42) == "42s")
        #expect(Formatting.compactRemaining(60) == "1m")
        #expect(Formatting.compactRemaining(61) == "2m")
        #expect(Formatting.compactRemaining(3_599) == "1h")
        #expect(Formatting.compactRemaining(3_600) == "1h")
        #expect(Formatting.compactRemaining(5_400) == "2h")
        #expect(Formatting.compactRemaining(86_399) == "1d")
        #expect(Formatting.compactRemaining(3.4 * 86_400) == "3d")
    }

    @Test func expiryLabelRelativeDays() {
        #expect(label(2 * 3_600 + 5 * 60) == "Today 14:05")
        #expect(label(86_400) == "Tomorrow 12:00")
        #expect(label(-86_400) == "Yesterday 12:00")
        #expect(label(3 * 86_400) == "Friday 12:00")
        #expect(label(30 * 86_400) == "Oct 29, 12:00")
        #expect(label(120 * 86_400) == "Jan 27, 2027, 12:00")
    }

    @Test func expiryLabelFollows12HourLocales() {
        let text = Formatting.expiryLabel(for: now.addingTimeInterval(7_500), now: now, calendar: calendar, timeLocale: enUS, textLocale: enUS)
        #expect(text.hasPrefix("Today 2:05"))
        #expect(text.hasSuffix("PM"))
    }

    @Test func agoLabel() {
        #expect(Formatting.agoLabel(for: now.addingTimeInterval(-10), now: now, locale: enUS) == "Just now")
        #expect(Formatting.agoLabel(for: now.addingTimeInterval(-7_200), now: now, locale: enUS) == "2 hours ago")
    }

    @Test func sizes() {
        #expect(Formatting.size(2_500_000, locale: enUS) == "2.5 MB")
        #expect(Formatting.size(0, locale: enUS).hasPrefix("Zero"))
    }
}
