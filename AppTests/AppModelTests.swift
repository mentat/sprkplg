import Foundation
import SparkPlugCore
import Testing
@testable import SparkPlug

/// A calendar service that keeps copied blocks in memory and records what was asked of it.
@MainActor
final class FakeCalendarService: CalendarService {
    var access: CalendarAccess = .granted
    var infos = [
        CalendarInfo(id: "work", title: "Work", source: "iCloud", colorHex: "#0a7cff", allowsModifications: true),
        CalendarInfo(id: "holidays", title: "Holidays", source: "Other", colorHex: "#ff3b30", allowsModifications: false),
    ]
    var stored: [CalendarEvent] = []
    var copies: [String: (task: TaskItem, calendar: String)] = [:]
    var removed: [String] = []
    private var next = 0

    func requestAccess() async -> CalendarAccess { access }
    func calendars() -> [CalendarInfo] { access == .granted ? infos : [] }
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        stored.filter { $0.start < end && $0.end > start }
    }
    func upsertCopy(of task: TaskItem, in calendarID: String) throws -> String {
        let id = task.copiedEventID.flatMap { copies[$0] != nil ? $0 : nil } ?? { next += 1; return "ev\(next)" }()
        copies[id] = (task, calendarID)
        return id
    }
    func removeCopy(eventID: String, taskID: UUID) throws {
        copies[eventID] = nil
        removed.append(eventID)
    }
    func onChange(_ handler: @escaping @MainActor () -> Void) {}
}

/// A clock the tests move by hand.
@MainActor
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
@Suite struct AppModelTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let service = FakeCalendarService()
    let clock: TestClock
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sparkplug-app-\(UUID().uuidString)")

    init() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        clock = TestClock(c.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10, minute: 40))!)
    }

    func at(_ hour: Double) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!.addingTimeInterval(hour * 3600)
    }

    func model(store: TaskStore? = nil, library: Library? = .starter(), ran: ShortcutLog? = nil) -> AppModel {
        let clock = self.clock
        let ran = ran ?? ShortcutLog()
        return AppModel(
            service: service, store: store, library: library, calendar: calendar, clock: { clock.now },
            runShortcut: { ran.names.append($0 ?? "<none>") }, isDemo: false, ticking: false)
    }

    @Test func quickEntryTakesTheLengthFromTheTitle() {
        let m = model()
        let id = m.addTask("Renew passport 20m", listID: m.library.lists[3].id, minutes: 30)!
        #expect(m.library.task(id)?.title == "Renew passport")
        #expect(m.library.task(id)?.minutes == 20)
        #expect(m.addTask("   ", listID: nil, minutes: 30) == nil)
        #expect(m.taskGroups.map(\.kind) == [.unscheduled])
    }

    @Test func schedulingSnapsAndRefusesBlocksThatAreAlreadyOver() {
        let m = model()
        let id = m.addTask("Draft roadmap", listID: nil, minutes: 90)!
        #expect(m.schedule(id, at: at(13 + 7.0 / 60)))
        #expect(m.library.task(id)?.start == at(13))
        let short = m.addTask("Quick call", listID: nil, minutes: 15)!
        #expect(!m.schedule(short, at: at(10)))  // 10:00–10:15, over at 10:40
        #expect(m.library.task(short)?.start == nil)
        #expect(m.plannedSummary == "1h 30m planned · 1 block")
    }

    @Test func aFinishedBlockSendsAnOpenTaskBackToTheList() {
        let m = model()
        let open = m.addTask("Reply to quotes", listID: nil, minutes: 60)!
        let done = m.addTask("Book flights", listID: nil, minutes: 30)!
        m.schedule(open, at: at(11))
        m.schedule(done, at: at(11))
        m.setDone(done, true)
        clock.now = at(12)
        m.tick()
        #expect(m.library.task(open)?.start == nil)
        #expect(m.library.task(done)?.start == at(11))
    }

    @Test func focusStartsNowOnTheFirstTaskAndRunsTheShortcuts() {
        let ran = ShortcutLog()
        let m = model(ran: ran)
        m.updateSettings {
            $0.focusOnShortcut = "DND On"
            $0.focusOffShortcut = "DND Off"
        }
        let id = m.addTask("Write copy", listID: nil, minutes: 60)!
        #expect(m.canFocus)
        m.toggleFocus()
        #expect(m.library.focus?.taskID == id)
        #expect(m.library.task(id)?.start == at(10 + 40.0 / 60))
        #expect(m.activeFocus(at: clock.now)?.secondsLeft == 3600)
        #expect(ran.names == ["DND On"])

        // The block ends: focus stops, Do Not Disturb goes off, the open task goes back.
        clock.now = at(11 + 40.0 / 60)
        m.tick()
        #expect(m.library.focus == nil)
        #expect(ran.names == ["DND On", "DND Off"])
        #expect(m.library.task(id)?.start == nil)
    }

    @Test func aFocusBlockStartsItselfButNotAgainAfterBeingStopped() {
        let ran = ShortcutLog()
        let m = model(ran: ran)
        let id = m.addTask("Deck", listID: nil, minutes: 120)!
        m.update(id) { $0.isFocusBlock = true }
        m.schedule(id, at: at(11))
        m.tick()
        #expect(m.library.focus == nil)  // not yet
        clock.now = at(11)
        m.tick()
        #expect(m.library.focus?.taskID == id)
        m.toggleFocus()
        #expect(m.library.focus == nil)
        m.tick()
        #expect(m.library.focus == nil)
        #expect(m.library.skippedFocusTaskIDs == [id])
        // Moved to later, it starts itself again when it begins.
        m.schedule(id, at: at(15))
        clock.now = at(11.5)
        m.tick()
        #expect(m.library.skippedFocusTaskIDs.isEmpty)
        clock.now = at(15)
        m.tick()
        #expect(m.library.focus?.taskID == id)
    }

    @Test func stoppingAPlainBlockDoesNotStartAnOverlappingFocusBlock() {
        let m = model()
        let plain = m.addTask("Plain", listID: nil, minutes: 60)!
        let deck = m.addTask("Deck", listID: nil, minutes: 60)!
        m.update(deck) { $0.isFocusBlock = true }
        m.schedule(plain, at: at(11))
        m.schedule(deck, at: at(11.25))
        clock.now = at(11)
        m.toggleFocus()
        #expect(m.library.focus?.taskID == plain)
        clock.now = at(11.5)  // the focus block has begun under the running session
        m.tick()
        #expect(m.library.focus?.taskID == plain)
        m.toggleFocus()
        m.tick()
        #expect(m.library.focus == nil)
        #expect(m.library.skippedFocusTaskIDs == [deck])
    }

    @Test func backToBackFocusBlocksHandOverWithoutTogglingDoNotDisturb() {
        let ran = ShortcutLog()
        let m = model(ran: ran)
        m.updateSettings {
            $0.focusOnShortcut = "On"
            $0.focusOffShortcut = "Off"
        }
        let a = m.addTask("A", listID: nil, minutes: 60)!
        let b = m.addTask("B", listID: nil, minutes: 60)!
        m.update(a) { $0.isFocusBlock = true }
        m.update(b) { $0.isFocusBlock = true }
        m.schedule(a, at: at(11))
        m.schedule(b, at: at(12))
        clock.now = at(11)
        m.tick()
        #expect(m.library.focus?.taskID == a)
        clock.now = at(12)
        m.tick()
        #expect(m.library.focus?.taskID == b)
        #expect(ran.names == ["On"])
        clock.now = at(13)
        m.tick()
        #expect(m.library.focus == nil)
        #expect(ran.names == ["On", "Off"])
    }

    @Test func startNowStartsOnTheMinute() {
        let m = model()
        let id = m.addTask("Now", listID: nil, minutes: 30)!
        m.schedule(id, at: clock.now.addingTimeInterval(25), snap: false)
        #expect(m.library.task(id)?.start == at(10 + 40.0 / 60))
    }

    @Test func aMissingCopyCalendarLeavesCopiesAlone() {
        let m = model()
        m.updateSettings { $0.copyCalendarID = "work" }
        let id = m.addTask("Roadmap", listID: nil, minutes: 60)!
        m.schedule(id, at: at(13))
        m.syncCopies()
        #expect(service.copies.count == 1)
        service.infos.removeAll { $0.id == "work" }  // the account is still syncing
        m.reloadCalendars()
        m.unschedule(id)
        m.syncCopies()
        #expect(service.copies.count == 1)
        #expect(m.library.task(id)?.copiedEventID != nil)
    }

    @Test func finishingTheFocusedTaskEndsFocus() {
        let ran = ShortcutLog()
        let m = model(ran: ran)
        let id = m.addTask("Roadmap", listID: nil, minutes: 60)!
        m.toggleFocus()
        m.setDone(id, true)
        #expect(m.library.focus == nil)
        #expect(ran.names.count == 2)
    }

    @Test func copiesFollowTheBlocksInTheChosenCalendar() {
        let m = model()
        let id = m.addTask("Roadmap", listID: nil, minutes: 60)!
        m.schedule(id, at: at(13))
        m.syncCopies()
        #expect(service.copies.isEmpty)  // copying is off by default

        m.updateSettings { $0.copyCalendarID = "work" }
        m.syncCopies()
        let eventID = m.library.task(id)?.copiedEventID
        #expect(eventID != nil)
        #expect(service.copies[eventID!]?.calendar == "work")

        m.schedule(id, at: at(15))
        m.syncCopies()
        #expect(service.copies[eventID!]?.task.start == at(15))
        #expect(m.library.task(id)?.copiedEventID == eventID)

        m.unschedule(id)
        m.syncCopies()
        #expect(service.copies.isEmpty)
        #expect(m.library.task(id)?.copiedEventID == nil)
    }

    @Test func copiesOfFinishedTasksStayAndDeletedTasksTakeTheirCopy() {
        let m = model()
        m.updateSettings { $0.copyCalendarID = "work" }
        let done = m.addTask("Done one", listID: nil, minutes: 60)!
        let gone = m.addTask("Deleted one", listID: nil, minutes: 60)!
        m.schedule(done, at: at(13))
        m.schedule(gone, at: at(15))
        m.syncCopies()
        m.setDone(done, true)
        m.updateSettings { $0.copyCalendarID = nil }
        m.syncCopies()
        #expect(service.copies.count == 1)  // the finished task's copy is a record; the open one's goes
        #expect(m.library.task(done)?.copiedEventID != nil)
        m.updateSettings { $0.copyCalendarID = "work" }
        m.syncCopies()
        let copy = m.library.task(gone)!.copiedEventID!
        m.delete(gone)
        #expect(service.removed.last == copy)
        #expect(m.library.task(gone) == nil)
    }

    @Test func readOnlyCalendarsAreNeverWrittenTo() {
        let m = model()
        m.updateSettings { $0.copyCalendarID = "holidays" }
        let id = m.addTask("Roadmap", listID: nil, minutes: 60)!
        m.schedule(id, at: at(13))
        m.syncCopies()
        #expect(service.copies.isEmpty)
    }

    @Test func ownCopiesAndHiddenCalendarsStayOffTheTimeline() {
        let m = model()
        let id = m.addTask("Roadmap", listID: nil, minutes: 60)!
        m.schedule(id, at: at(13))
        service.stored = [
            CalendarEvent(id: "a", title: "Standup", start: at(9), end: at(9.5), calendarID: "work"),
            CalendarEvent(id: "b", title: "Roadmap", start: at(13), end: at(14), calendarID: "work", taskID: id),
            CalendarEvent(id: "c", title: "Holiday", start: at(0), end: at(24), isAllDay: true, calendarID: "holidays"),
        ]
        m.reloadCalendars()
        var items = m.items(on: at(12))
        #expect(items.timed.map(\.title).sorted() == ["Roadmap", "Standup"])
        #expect(items.allDay.map(\.title) == ["Holiday"])
        m.toggleCalendar("holidays")
        items = m.items(on: at(12))
        #expect(items.allDay.isEmpty)
        #expect(m.isHidden("holidays"))
    }

    @Test func deletingAListKeepsItsTasks() {
        let m = model()
        let work = m.library.lists[0].id
        let id = m.addTask("Roadmap", listID: work, minutes: 60)!
        m.selection = .list(work)
        #expect(m.title == "Work" && m.subtitle == "1 open task")
        m.deleteList(work)
        #expect(m.selection == .today)
        #expect(m.library.task(id)?.listID == nil)
        #expect(m.library.lists.count == 3)
        let added = m.addList(named: "Side project")
        #expect(m.library.list(added)?.colorHex == "#5b5fe6")  // the colour the deleted list freed
    }

    @Test func savesAndReloads() throws {
        let store = TaskStore(url: dir.appendingPathComponent("library.json"))
        let m = model(store: store, library: nil)
        let id = m.addTask("Persist me 45m", listID: nil, minutes: 30)!
        m.saveNow()
        let again = model(store: store, library: nil)
        #expect(again.library.task(id)?.minutes == 45)
        #expect(again.storeProblem == nil)
    }

    @Test func aNewerLibraryIsNeverOverwritten() throws {
        let url = dir.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let original = Data(#"{"version":42}"#.utf8)
        try original.write(to: url)
        let m = model(store: TaskStore(url: url), library: nil)
        #expect(m.storeProblem != nil)
        #expect(m.notice != nil)
        m.addTask("Not saved", listID: nil, minutes: 30)
        m.saveNow()
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func withoutCalendarAccessTasksStillWork() {
        service.access = .denied
        let m = model()
        #expect(m.calendars.isEmpty)
        let id = m.addTask("Offline", listID: nil, minutes: 30)!
        #expect(m.schedule(id, at: at(14)))
        m.updateSettings { $0.copyCalendarID = "work" }
        m.syncCopies()
        #expect(service.copies.isEmpty)
    }
}

/// Shortcut names the model asked to run.
@MainActor
final class ShortcutLog {
    var names: [String] = []
}
