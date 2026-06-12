import Foundation

/// Islamic (Hijri) date formatting using the Umm al-Qura calendar — the official Saudi
/// civil calendar and the most widely accepted algorithmic Hijri. Because any algorithmic
/// calendar can differ ±1 day from a local moon-sighting announcement, callers can pass a
/// manual `dayAdjustment` (surfaced as a Settings control) to align with their authority.
enum HijriDate {
    private static func calendar(timeZone: TimeZone, locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    /// e.g. "15 Ramadan 1447". Month names localize automatically via the calendar.
    static func formatted(
        for date: Date = Date(),
        dayAdjustment: Int = 0,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let calendar = calendar(timeZone: timeZone, locale: locale)
        let adjusted = calendar.date(byAdding: .day, value: dayAdjustment, to: date) ?? date

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMMM y"
        return formatter.string(from: adjusted)
    }

    static func components(
        for date: Date = Date(),
        dayAdjustment: Int = 0,
        timeZone: TimeZone = .current
    ) -> (day: Int, month: Int, year: Int) {
        let calendar = calendar(timeZone: timeZone, locale: .current)
        let adjusted = calendar.date(byAdding: .day, value: dayAdjustment, to: date) ?? date
        let c = calendar.dateComponents([.day, .month, .year], from: adjusted)
        return (c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }
}
