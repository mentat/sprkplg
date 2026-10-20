import Foundation
import Testing
@testable import SparkPlugCore

@Suite struct DayLayoutTests {
    let layout = DayLayout(calendar: nyCalendar, hourHeight: 60)
    let day = oct20(0)
    let workday = HourRange(start: 8, end: 18)

    func item(_ id: String, _ s: Double, _ e: Double, day: Int = 20) -> TimelineItem {
        TimelineItem(id: id, kind: .event(calendarID: "c"), title: id, start: oct20(s, day: day), end: oct20(e, day: day))
    }

    @Test func blocksSitAtTheirTimeLikeTheDesign() {
        // The design: top = (start - 8h) * 60 + 1, height = length * 60 - 3.
        let placed = layout.place([item("standup", 9, 9.5)], day: day, range: workday)
        #expect(placed.count == 1)
        #expect(placed[0].top == 61)
        #expect(placed[0].height == 27)
        #expect(placed[0].column == 0 && placed[0].columns == 1)
    }

    @Test func overlappingItemsShareColumnsPerGroup() {
        let items = [
            item("a", 9, 10), item("b", 9.5, 10.5), item("c", 10, 11),  // a|b, then c reuses a's column
            item("d", 13, 14),  // alone: full width
        ]
        let placed = Dictionary(uniqueKeysWithValues: layout.place(items, day: day, range: workday).map { ($0.id, $0) })
        #expect(placed["a"]!.column == 0 && placed["a"]!.columns == 2)
        #expect(placed["b"]!.column == 1 && placed["b"]!.columns == 2)
        #expect(placed["c"]!.column == 0 && placed["c"]!.columns == 2)
        #expect(placed["d"]!.column == 0 && placed["d"]!.columns == 1)
    }

    @Test func longerItemTakesTheFirstColumnWhenStartsTie() {
        let placed = layout.place([item("short", 9, 9.5), item("long", 9, 11)], day: day, range: workday)
        #expect(placed.map(\.id) == ["long", "short"])
        #expect(placed[0].column == 0 && placed[1].column == 1)
    }

    @Test func itemsAreClippedToTheVisibleHoursAndTinyOnesStayClickable() {
        let placed = layout.place(
            [item("early", 7, 9), item("late", 17.5, 20), item("gone", 5, 6), item("blip", 12, 12.05)], day: day,
            range: workday)
        let byID = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
        #expect(byID["gone"] == nil)
        #expect(byID["early"]!.top == 1 && byID["early"]!.height == 57)
        #expect(byID["late"]!.top == 571 && byID["late"]!.height == 27)
        #expect(byID["blip"]!.height == 14)
    }

    @Test func hourRangeWidensToFitTheDay() {
        #expect(layout.hourRange(for: [], days: [day], minimum: (8, 18)) == HourRange(start: 8, end: 18))
        let r = layout.hourRange(for: [item("gym", 6.5, 7.5), item("dinner", 19, 20.25)], days: [day], minimum: (8, 18))
        #expect(r == HourRange(start: 6, end: 21))
        // An overnight item on another day of the range opens the whole night.
        let overnight = TimelineItem(id: "o", kind: .event(calendarID: "c"), title: "o", start: oct20(22), end: oct20(26))
        #expect(layout.hourRange(for: [overnight], days: [day], minimum: (8, 18)) == HourRange(start: 8, end: 24))
        #expect(
            layout.hourRange(for: [overnight], days: [oct20(0, day: 21)], minimum: (8, 18)) == HourRange(start: 0, end: 18))
        // Items on other days do not count.
        #expect(layout.hourRange(for: [item("x", 5, 6, day: 22)], days: [day], minimum: (8, 18)).start == 8)
    }

    @Test func dropsSnapToQuarterHours() {
        #expect(layout.time(atY: 0, day: day, range: workday) == oct20(8))
        #expect(layout.time(atY: 97, day: day, range: workday) == oct20(9.5))  // 9:37 → 9:30
        #expect(layout.time(atY: 98, day: day, range: workday) == oct20(9.75))  // 9:38 → 9:45
        #expect(layout.time(atY: -40, day: day, range: workday) == oct20(8))
        #expect(layout.time(atY: 9999, day: day, range: workday) == oct20(18))
    }

    @Test func nowLinePosition() {
        #expect(layout.y(of: oct20(10 + 40.0 / 60), day: day, range: workday) == 160)
    }

    @Test func clockChangeDaysKeepTheHourLabelsTrue() {
        // 8 March 2026: New York springs forward at 2 AM, so the day has 23 hours.
        let spring = nyCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let nineAM = nyCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9))!
        #expect(layout.origin(of: spring, range: workday) == nyCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: spring))
        #expect(layout.y(of: nineAM, day: spring, range: workday) == 60)
        #expect(layout.time(atY: 60, day: spring, range: workday) == nineAM)
        let ev = TimelineItem(id: "e", kind: .event(calendarID: "c"), title: "e", start: nineAM, end: nineAM.addingTimeInterval(1800))
        #expect(layout.place([ev], day: spring, range: workday).first?.top == 61)
        // 1 November 2026: clocks fall back at 2 AM (a 25-hour day).
        let fall = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let fallNine = nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
        #expect(layout.y(of: fallNine, day: fall, range: workday) == 60)
        #expect(layout.time(atY: 9999, day: fall, range: workday) == nyCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18)))
    }
}
