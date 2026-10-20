import Foundation
import Testing
@testable import SparkPlugCore

@Suite struct PlannerTests {
    let planner = Planner(calendar: nyCalendar)
    let now = oct20(10 + 40.0 / 60)  // Tuesday 10:40 AM

    @Test func groupsFollowTheDesign() {
        let roadmap = task("Draft Q4 roadmap", minutes: 90, start: oct20(9.5))
        let quotes = task("Reply to contractor quotes", minutes: 60, start: oct20(13.5))
        let passport = task("Renew passport", minutes: 20, created: 2)
        let bank = task("Call the bank", minutes: 10, created: 1)
        let friday = task("Plan Sam's birthday", start: oct20(13, day: 23))
        let flights = task("Book flights", doneAt: oct20(8))
        let yesterday = task("Old", doneAt: oct20(8, day: 19))
        let missed = task("Missed", start: oct20(9, day: 19))  // a past day's block counts as unscheduled

        let groups = planner.groups([passport, quotes, friday, flights, roadmap, bank, yesterday, missed], now: now)
        #expect(groups.map(\.kind) == [.scheduled, .unscheduled, .later, .done])
        #expect(groups[0].tasks.map(\.title) == ["Draft Q4 roadmap", "Reply to contractor quotes"])
        #expect(groups[1].tasks.map(\.title) == ["Missed", "Call the bank", "Renew passport"])
        #expect(groups[2].tasks.map(\.title) == ["Plan Sam's birthday"])
        #expect(groups[3].tasks.map(\.title) == ["Book flights"])
        #expect(groups[0].title == "Scheduled today")
    }

    @Test func emptyGroupsAreLeftOut() {
        #expect(planner.groups([], now: now).isEmpty)
        #expect(planner.groups([task("a")], now: now).map(\.kind) == [.unscheduled])
    }

    @Test func plannedSummaryAndCounts() {
        let work = UUID()
        let tasks = [
            task("a", minutes: 90, start: oct20(9.5), list: work), task("b", minutes: 45, start: oct20(13)),
            task("c", list: work), task("d", start: oct20(9, day: 22)), task("e", doneAt: now, list: work),
        ]
        #expect(planner.plannedSummary(tasks, now: now) == "2h 15m planned · 2 blocks")
        #expect(planner.plannedSummary([tasks[0]], now: now) == "1h 30m planned · 1 block")
        #expect(planner.plannedSummary([], now: now) == "Nothing planned")
        #expect(planner.todayCount(tasks, now: now) == 3)
        #expect(planner.openCounts(tasks) == [work: 2])
    }

    @Test func filterByListAndSearch() {
        let errands = TaskList(name: "Errands", colorHex: "#a35bd9")
        let tasks = [task("Renew passport", list: errands.id), task("Draft roadmap"), task("Dry cleaning", list: errands.id)]
        #expect(planner.filter(tasks, listID: errands.id, search: "", lists: [errands]).count == 2)
        #expect(planner.filter(tasks, listID: nil, search: "ROAD", lists: [errands]).map(\.title) == ["Draft roadmap"])
        #expect(planner.filter(tasks, listID: nil, search: "errand", lists: [errands]).count == 2)
        #expect(planner.filter(tasks, listID: nil, search: "  ", lists: [errands]).count == 3)
    }

    @Test func finishedBlocksWithOpenTasksGoBackToTheList() {
        let over = task("over", minutes: 30, start: oct20(10))  // ended 10:30
        let endsNow = task("ends now", minutes: 40, start: oct20(10))  // ends 10:40
        let running = task("running", minutes: 90, start: oct20(9.5))
        let doneEarlier = task("done", minutes: 30, start: oct20(9), doneAt: oct20(9.4))
        let lastWeek = task("last week", start: oct20(9, day: 13))
        let ids = planner.expired([over, endsNow, running, doneEarlier, lastWeek, task("list")], now: now)
        #expect(Set(ids) == [over.id, endsNow.id, lastWeek.id])
    }

    @Test func blocksCannotBePutWhereTheyAreAlreadyOver() {
        #expect(!planner.canSchedule(start: oct20(10), minutes: 30, now: now))
        #expect(planner.canSchedule(start: oct20(10.5), minutes: 30, now: now))
        #expect(planner.canSchedule(start: oct20(14), minutes: 30, now: now))
    }

    @Test func snapRoundsToTheNearestQuarter() {
        #expect(planner.snap(oct20(10 + 7.0 / 60)) == oct20(10))
        #expect(planner.snap(oct20(10 + 8.0 / 60)) == oct20(10.25))
        #expect(planner.snap(oct20(23 + 59.0 / 60)) == oct20(24))
    }

    @Test func focusTargetsTheCurrentBlockThenTheFirstUnscheduledTask() {
        let running = task("running", minutes: 90, start: oct20(9.5))
        let focusBlock = task("focus", minutes: 60, start: oct20(10.5), focus: true)
        let first = task("first", created: 1)
        let second = task("second", created: 2)
        #expect(planner.focusTarget([second, running, first], now: now) == .current(running.id))
        #expect(planner.focusTarget([running, focusBlock], now: now) == .current(focusBlock.id))
        #expect(planner.focusTarget([second, first], now: now) == .startNow(first.id))
        #expect(planner.focusTarget([task("done", doneAt: now)], now: now) == nil)
    }

    @Test func focusBlocksStartThemselvesUnlessStoppedByHand() {
        let block = task("Deck", minutes: 120, start: oct20(10), focus: true)
        let plain = task("Plain", minutes: 120, start: oct20(10))
        #expect(planner.autoFocus([plain, block], now: now, skipped: []) == block.id)
        #expect(planner.autoFocus([plain, block], now: now, skipped: [block.id]) == nil)
        #expect(planner.autoFocus([plain], now: now, skipped: []) == nil)
    }

    @Test func activeFocusCountsDown() {
        let roadmap = task("Draft Q4 roadmap", minutes: 90, start: oct20(9.5))
        let focus = Focus(taskID: roadmap.id, startedAt: oct20(9.5))
        let at = oct20(9.5).addingTimeInterval(90 * 60 - 1188)  // the design's 19:48 left
        let active = planner.active(focus, tasks: [roadmap], now: at)
        #expect(active?.secondsLeft == 1188)
        #expect(abs((active?.progress ?? 0) - 0.78) < 0.001)
        #expect(planner.active(focus, tasks: [roadmap], now: oct20(11)) == nil)  // block over
        var done = roadmap
        done.doneAt = at
        #expect(planner.active(focus, tasks: [done], now: at) == nil)
        #expect(planner.active(focus, tasks: [], now: at) == nil)
        #expect(planner.active(nil, tasks: [roadmap], now: at) == nil)
    }

    @Test func timelineItemsHideOwnCopiesAndHiddenCalendars() {
        var block = task("Roadmap", minutes: 90, start: oct20(9.5), focus: false)
        block.copiedEventID = "EK-7"
        let events = [
            CalendarEvent(
                id: "7", title: "Roadmap (marker lost in sync)", start: oct20(9.5), end: oct20(11), calendarID: "work",
                eventID: "EK-7"),
            CalendarEvent(id: "1", title: "Standup", start: oct20(9), end: oct20(9.5), calendarID: "work"),
            CalendarEvent(id: "2", title: "Dentist", start: oct20(15.25), end: oct20(16), calendarID: "family"),
            CalendarEvent(id: "3", title: "Roadmap", start: oct20(9.5), end: oct20(11), calendarID: "work", taskID: block.id),
            CalendarEvent(id: "4", title: "Orphan copy", start: oct20(12), end: oct20(13), calendarID: "work", taskID: UUID()),
            CalendarEvent(id: "5", title: "Holiday", start: oct20(0), end: oct20(24), isAllDay: true, calendarID: "work"),
            CalendarEvent(id: "6", title: "Tomorrow", start: oct20(9, day: 21), end: oct20(10, day: 21), calendarID: "work"),
        ]
        let (timed, allDay) = planner.items(
            on: oct20(0), tasks: [block], events: events, hidden: ["family"], activeFocus: block.id)
        #expect(Set(timed.map(\.title)) == ["Standup", "Orphan copy", "Roadmap"])
        #expect(allDay.map(\.title) == ["Holiday"])
        let roadmap = timed.first { $0.taskID == block.id }!
        #expect(roadmap.isFocus && roadmap.isActiveFocus)
    }

    @Test func weekStartsOnMonday() {
        let days = planner.week(containing: now, weekends: false)
        #expect(days == [19, 20, 21, 22, 23].map { oct20(0, day: $0) })
        #expect(planner.week(containing: oct20(12, day: 25), weekends: true).count == 7)
        #expect(planner.week(containing: oct20(12, day: 25), weekends: true).first == oct20(0, day: 19))
    }

    @Test func dueChips() {
        let a = task("Pay rent", due: oct20(0, day: 23), created: 2)
        let b = task("Expense report", due: oct20(17, day: 23), created: 1)
        let done = task("Done", due: oct20(0, day: 23), doneAt: now)
        #expect(planner.due(on: oct20(0, day: 23), [a, b, done]).map(\.title) == ["Expense report", "Pay rent"])
        #expect(planner.due(on: oct20(0, day: 22), [a, b]).isEmpty)
    }

    @Test(arguments: [
        ("Renew passport 20m", "Renew passport", 20 as Int?),
        ("Write onboarding copy 2h", "Write onboarding copy", 120),
        ("Draft roadmap 1h30m", "Draft roadmap", 90),
        ("Draft roadmap 1h 30m", "Draft roadmap", 90),
        ("Review 1.5h", "Review", 90),
        ("Call the bank 10 min", "Call the bank", 10),
        ("Gym 45 MINUTES", "Gym", 45),
        ("Plan Sam's birthday", "Plan Sam's birthday", nil),
        ("Call 10", "Call 10", nil),
        ("20m", "20m", nil),
        ("  Trim me  ", "Trim me", nil),
        ("Nap 0m", "Nap 0m", nil),
        ("Overflow 99999999999999999999h", "Overflow 99999999999999999999h", nil),
        ("Overflow 99999999999999999999m", "Overflow 99999999999999999999m", nil),
        ("Too long 30h", "Too long 30h", nil),
    ])
    func quickEntry(text: String, title: String, minutes: Int?) {
        let parsed = Planner.parseQuickEntry(text)
        #expect(parsed.title == title)
        #expect(parsed.minutes == minutes)
    }
}
