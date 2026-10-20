import Foundation

/// How SparkPlug writes times, lengths and dates: "9:30 AM", "9:30 – 11 AM", "1h 30m",
/// "Tuesday, October 20". The 12-hour forms follow the design; 24-hour locales get "09:30".
public struct TimeFormat: Sendable {
    public var calendar: Calendar
    public var locale: Locale
    public var uses12Hour: Bool

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        self.uses12Hour = pattern.contains("a")
    }

    private func parts(_ date: Date) -> (hour: Int, minute: Int) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    private func suffix(_ hour: Int) -> String { hour < 12 ? "AM" : "PM" }

    /// "9 AM", "9:30 AM" — or "09:00", "09:30".
    public func time(_ date: Date) -> String {
        let (h, m) = parts(date)
        guard uses12Hour else { return String(format: "%02d:%02d", h, m) }
        return "\(shortTime(date)) \(suffix(h))"
    }

    /// "9", "9:30" — the 12-hour time without AM/PM, used where the context gives it.
    public func shortTime(_ date: Date) -> String {
        let (h, m) = parts(date)
        guard uses12Hour else { return String(format: "%02d:%02d", h, m) }
        let hh = h % 12 == 0 ? 12 : h % 12
        return m == 0 ? "\(hh)" : "\(hh):" + String(format: "%02d", m)
    }

    /// "9:30 – 11 AM"; the start keeps its AM/PM when the two differ ("11:30 AM – 12:30 PM").
    public func range(_ start: Date, _ end: Date) -> String {
        guard uses12Hour else { return "\(time(start)) – \(time(end))" }
        let sameHalf = suffix(parts(start).hour) == suffix(parts(end).hour)
        return "\(sameHalf ? shortTime(start) : time(start)) – \(time(end))"
    }

    /// The timeline's hour labels: "8 AM", "12 PM" — or "08:00". `24` is midnight at the end of the day.
    public func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        guard uses12Hour else { return String(format: "%02d:00", h) }
        return "\(h % 12 == 0 ? 12 : h % 12) \(suffix(h))"
    }

    /// "45m", "1h", "1h 30m".
    public static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// A countdown: "19:48", or "1:02:03" past an hour.
    public static func countdown(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// "Tuesday, October 20".
    public func dayTitle(_ date: Date) -> String {
        formatter("EEEEMMMMd").string(from: date)
    }

    /// "October 19 – 23".
    public func weekTitle(from start: Date, to end: Date) -> String {
        let f = DateIntervalFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateTemplate = "MMMMd"
        // The formatter puts thin spaces around the dash; the design uses plain ones.
        return f.string(from: start, to: end).replacingOccurrences(of: "\u{2009}", with: " ")
    }

    /// "MON".
    public func weekday(_ date: Date) -> String {
        formatter("EEE").string(from: date).uppercased(with: locale)
    }

    /// "Oct 23".
    public func shortDate(_ date: Date) -> String {
        formatter("MMMd").string(from: date)
    }
}
