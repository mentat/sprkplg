import Foundation

/// Something drawn on the timeline: a calendar event or a task's block.
public struct TimelineItem: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case event(calendarID: String)
        case task(UUID)
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var start: Date
    public var end: Date
    public var isDone: Bool
    /// A task marked as a focus block, or the task Focus is running on.
    public var isFocus: Bool
    /// The task Focus is running on right now.
    public var isActiveFocus: Bool

    public init(
        id: String, kind: Kind, title: String, start: Date, end: Date, isDone: Bool = false, isFocus: Bool = false,
        isActiveFocus: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isDone = isDone
        self.isFocus = isFocus
        self.isActiveFocus = isActiveFocus
    }

    public var taskID: UUID? {
        if case .task(let id) = kind { return id }
        return nil
    }
}

/// A timeline item with its place: `top`/`height` in points from the top of the visible hours,
/// and its column when items overlap (`column` of `columns`, side by side).
public struct PlacedItem: Hashable, Identifiable, Sendable {
    public var item: TimelineItem
    public var top: Double
    public var height: Double
    public var column: Int
    public var columns: Int

    public var id: String { item.id }
}

/// The visible hours of a timeline: `start` ..< `end`, as hours of the day (0…24).
public struct HourRange: Hashable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var count: Int { end - start }
    public var hours: ClosedRange<Int> { start...end }
}

/// Puts a day's items on a vertical timeline (`hourHeight` points per hour).
public struct DayLayout: Sendable {
    public var calendar: Calendar
    public var hourHeight: Double

    public init(calendar: Calendar = .autoupdatingCurrent, hourHeight: Double = 60) {
        self.calendar = calendar
        self.hourHeight = hourHeight
    }

    /// The hours to show for `days`: at least the settings' hours, widened to whole hours so that
    /// every item that touches one of those days fits.
    public func hourRange(for items: [TimelineItem], days: [Date], minimum: (Int, Int)) -> HourRange {
        var lo = minimum.0, hi = minimum.1
        for day in days {
            let dayStart = calendar.startOfDay(for: day)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            for item in items where item.start < dayEnd && item.end > dayStart {
                let s = item.start <= dayStart ? 0 : calendar.component(.hour, from: item.start)
                let e: Int
                if item.end >= dayEnd {
                    e = 24
                } else {
                    let c = calendar.dateComponents([.hour, .minute, .second], from: item.end)
                    e = (c.hour ?? 0) + ((c.minute ?? 0) > 0 || (c.second ?? 0) > 0 ? 1 : 0)
                }
                lo = min(lo, s)
                hi = max(hi, e)
            }
        }
        let (s, e) = Preferences.clampHours(lo, hi)
        return HourRange(start: s, end: e)
    }

    /// The wall-clock time `minutes` after midnight on `day` (1440 is the next midnight). On the
    /// days the clocks change, times are placed by what the clock says, as Calendar does, so the
    /// hour labels stay true.
    public func date(minutes: Int, on day: Date) -> Date {
        let start = calendar.startOfDay(for: day)
        let m = min(max(minutes, 0), 1440)
        if m == 1440 { return calendar.date(byAdding: .day, value: 1, to: start) ?? start }
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(m * 60))
    }

    /// The wall-clock minutes of `date` counted from midnight on `day`: before the day is
    /// below 0, after it is 1440 or more.
    public func minutes(of date: Date, on day: Date) -> Double {
        let start = calendar.startOfDay(for: day)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let whole: Int = days * 1440 + (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let seconds: Double = Double(c.second ?? 0)
        return Double(whole) + seconds / 60
    }

    /// The moment at the top of the timeline for `day`.
    public func origin(of day: Date, range: HourRange) -> Date {
        date(minutes: range.start * 60, on: day)
    }

    /// The y position of `date` on `day`'s timeline.
    public func y(of date: Date, day: Date, range: HourRange) -> Double {
        (minutes(of: date, on: day) - Double(range.start * 60)) / 60 * hourHeight
    }

    /// The time at `y` on `day`'s timeline, rounded to the nearest `snap` minutes and kept on the
    /// visible hours.
    public func time(atY y: Double, day: Date, range: HourRange, snap: Int = 15) -> Date {
        let maxY = Double(range.count) * hourHeight
        let minutes = min(max(y, 0), maxY) / hourHeight * 60
        let snapped = Int((minutes / Double(snap)).rounded()) * snap
        return date(minutes: range.start * 60 + snapped, on: day)
    }

    /// Places `items` on `day`'s timeline. Items are clipped to the visible hours; overlapping
    /// items share the width in columns, each overlap group sized to its own widest moment.
    public func place(_ items: [TimelineItem], day: Date, range: HourRange) -> [PlacedItem] {
        let top = origin(of: day, range: range)
        let bottom = date(minutes: range.end * 60, on: day)
        let visible = items
            .filter { $0.end > top && $0.start < bottom && $0.end > $0.start }
            .sorted { a, b in
                a.start != b.start ? a.start < b.start : (a.end != b.end ? a.end > b.end : a.id < b.id)
            }

        var placed: [PlacedItem] = []
        var group: [Int] = []  // indexes into `placed` of the current overlap group
        var columnEnds: [Date] = []
        var groupEnd = Date.distantPast

        func closeGroup() {
            for i in group { placed[i].columns = columnEnds.count }
            group = []
            columnEnds = []
        }

        for item in visible {
            if item.start >= groupEnd { closeGroup() }
            let column = columnEnds.firstIndex { $0 <= item.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(item.end) } else { columnEnds[column] = item.end }
            groupEnd = max(groupEnd, item.end)

            let maxY = Double(range.count) * hourHeight
            let y = min(max(self.y(of: item.start, day: day, range: range), 0), maxY)
            let h = min(max(self.y(of: item.end, day: day, range: range), 0), maxY) - y
            placed.append(PlacedItem(item: item, top: y + 1, height: max(h - 3, 14), column: column, columns: 1))
            group.append(placed.count - 1)
        }
        closeGroup()
        return placed
    }
}
