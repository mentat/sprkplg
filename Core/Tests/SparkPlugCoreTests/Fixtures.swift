import Foundation
@testable import SparkPlugCore

/// A fixed calendar (New York, Gregorian, en_US) so tests mean the same thing on every machine.
let nyCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    c.locale = Locale(identifier: "en_US")
    return c
}()

/// Tuesday 20 October 2026 at `hour` (fractional hours allowed: 9.5 = 9:30).
func oct20(_ hour: Double, day: Int = 20) -> Date {
    let base = nyCalendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    return base.addingTimeInterval(hour * 3600)
}

func task(
    _ title: String, minutes: Int = 30, start: Date? = nil, due: Date? = nil, focus: Bool = false,
    doneAt: Date? = nil, created: Double = 0, list: UUID? = nil
) -> TaskItem {
    TaskItem(
        title: title, listID: list, minutes: minutes, start: start, due: due, isFocusBlock: focus, doneAt: doneAt,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000 + created))
}
