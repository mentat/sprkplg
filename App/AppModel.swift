import AppKit
import Observation
import SparkPlugCore
import os

private let log = Logger(subsystem: "io.sprkplg.SparkPlug", category: "model")

/// The app's state and every change to it. Views read from here and call its methods; the rules
/// themselves live in SparkPlugCore's `Planner`.
@MainActor
@Observable
final class AppModel {
    enum Section: Hashable {
        case today, week
        case list(UUID)
    }

    private(set) var library: Library
    var selection: Section = .today
    var search = ""
    private(set) var calendars: [CalendarInfo] = []
    private(set) var events: [CalendarEvent] = []
    private(set) var access: CalendarAccess
    /// The current minute. Views that tick every second read `clock()` inside a `TimelineView`.
    private(set) var now: Date
    /// The quick-entry row at the top of the task list is open.
    var isAddingTask = false
    /// The task row being dragged onto the timeline.
    var draggingTaskID: UUID?
    /// The block being moved on the timeline (so its day column draws above the others).
    var movingTaskID: UUID?
    /// Set when the library cannot be saved (a newer SparkPlug wrote it); changes stay in memory.
    private(set) var storeProblem: String?
    /// A one-off message for an alert.
    var notice: String?

    let isDemo: Bool
    let planner: Planner
    let layout: DayLayout
    let format: TimeFormat
    private let service: CalendarService
    private let store: TaskStore?
    private let now_: () -> Date
    private let runShortcut: (String?) -> Void
    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var eventsDay: Date
    private var quitObserver: NSObjectProtocol?

    /// The app as launched: your calendars and saved tasks, or (`demo`) the sample week.
    convenience init(demo: Bool) {
        let calendar = Calendar.autoupdatingCurrent
        if demo {
            let offset = DemoData.now(calendar: calendar).timeIntervalSinceNow
            self.init(
                service: DemoCalendarService(), store: nil, library: DemoData.library(calendar: calendar),
                calendar: calendar, clock: { Date().addingTimeInterval(offset) }, runShortcut: { _ in }, isDemo: true)
            return
        }
        let store = try? TaskStore(url: TaskStore.defaultURL())
        self.init(
            service: EventKitCalendarService(), store: store, library: nil, calendar: calendar, clock: { Date() },
            runShortcut: ShortcutRunner.run, isDemo: false)
        if store == nil { storeProblem = "SparkPlug can't find its Application Support folder, so changes won't be saved." }
    }

    /// - Parameters:
    ///   - store: where the library is saved; nil saves nothing.
    ///   - library: the library to start with; nil loads it from `store`.
    ///   - ticking: runs the once-a-second clock (tests call `tick()` themselves).
    init(
        service: CalendarService, store: TaskStore?, library: Library?, calendar: Calendar,
        clock: @escaping () -> Date, runShortcut: @escaping (String?) -> Void, isDemo: Bool, ticking: Bool = true
    ) {
        self.isDemo = isDemo
        self.service = service
        self.store = store
        self.now_ = clock
        self.runShortcut = runShortcut
        planner = Planner(calendar: calendar)
        layout = DayLayout(calendar: calendar, hourHeight: 60)
        format = TimeFormat(calendar: calendar)
        let start = clock()
        now = start
        eventsDay = calendar.startOfDay(for: start)
        access = service.access

        if let library {
            self.library = library
        } else if let store {
            self.library = .starter()
            do {
                switch try store.load() {
                case .fresh(let l), .loaded(let l):
                    self.library = l
                case .recovered(let l, let aside):
                    self.library = l
                    notice = "SparkPlug couldn't read its saved tasks, so it started fresh. The old file is at \(aside.path)."
                }
            } catch {
                // A newer SparkPlug's file, or one that could not be moved aside: never overwrite it.
                storeProblem = "\(error)"
                notice = "SparkPlug can't open its saved tasks: \(error) Changes you make now won't be saved."
                log.error("library not loaded: \(String(describing: error), privacy: .public)")
            }
        } else {
            self.library = .starter()
        }
        now = minute(of: start)
        service.onChange { [weak self] in self?.reloadCalendars() }
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        reloadCalendars()
        tick()
        if ticking {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    self?.tick()
                }
            }
        }
    }

    /// The time now (the demo runs on its own clock).
    func clock() -> Date { now_() }

    private func minute(of date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    // MARK: - The clock

    /// Once a second: keeps `now` current, ends focus when its block does, sends finished blocks
    /// back to the list, and starts focus blocks as they begin.
    func tick() {
        let t = clock()
        let m = minute(of: t)
        if m != now { now = m }
        if !planner.calendar.isDate(t, inSameDayAs: eventsDay) { reloadEvents() }

        // Focus blocks stopped by hand stay stopped only while they are happening.
        let stillSkipped = library.skippedFocusTaskIDs.filter { id in library.task(id)?.covers(t) ?? false }
        if stillSkipped != library.skippedFocusTaskIDs { mutate { $0.skippedFocusTaskIDs = stillSkipped } }

        let ended = library.focus != nil && planner.active(library.focus, tasks: library.tasks, now: t) == nil
        let expired = planner.expired(library.tasks, now: t)
        if !expired.isEmpty {
            mutate { lib in
                for i in lib.tasks.indices where expired.contains(lib.tasks[i].id) { lib.tasks[i].start = nil }
            }
        }
        let next = (ended || library.focus == nil)
            ? planner.autoFocus(library.tasks, now: t, skipped: library.skippedFocusTaskIDs) : nil
        if ended, let next {
            // One block hands straight over to a focus block: Do Not Disturb stays on.
            mutate { $0.focus = Focus(taskID: next, startedAt: t) }
        } else if ended {
            stopFocus()
        } else if let next {
            startFocus(next)
        }
    }

    // MARK: - Calendars

    func requestCalendarAccess() async {
        access = await service.requestAccess()
        reloadCalendars()
    }

    func reloadCalendars() {
        access = service.access
        calendars = service.calendars()
        reloadEvents()
        scheduleCopySync()
    }

    private func reloadEvents() {
        let week = planner.week(containing: clock(), weekends: true)
        guard let first = week.first, let last = week.last,
            let end = planner.calendar.date(byAdding: .day, value: 1, to: last)
        else { return }
        events = service.events(from: first, to: end)
        eventsDay = planner.calendar.startOfDay(for: clock())
    }

    func isHidden(_ calendarID: String) -> Bool {
        library.settings.hiddenCalendarIDs.contains(calendarID)
    }

    func toggleCalendar(_ calendarID: String) {
        mutate { lib in
            if lib.settings.hiddenCalendarIDs.contains(calendarID) {
                lib.settings.hiddenCalendarIDs.remove(calendarID)
            } else {
                lib.settings.hiddenCalendarIDs.insert(calendarID)
            }
        }
    }

    func calendarHex(_ id: String) -> String {
        calendars.first { $0.id == id }?.colorHex ?? "#8e8e93"
    }

    // MARK: - Tasks

    /// Adds a task from the quick-entry row. A length typed at the end ("… 20m") wins over `minutes`.
    @discardableResult
    func addTask(_ text: String, listID: UUID?, minutes: Int) -> UUID? {
        let parsed = Planner.parseQuickEntry(text)
        guard !parsed.title.isEmpty else { return nil }
        let task = TaskItem(title: parsed.title, listID: listID, minutes: parsed.minutes ?? minutes, createdAt: clock())
        mutate { $0.tasks.append(task) }
        return task.id
    }

    func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        mutate { lib in
            guard let i = lib.tasks.firstIndex(where: { $0.id == id }) else { return }
            change(&lib.tasks[i])
            lib.tasks[i].minutes = max(5, lib.tasks[i].minutes)
            lib.tasks[i].title = lib.tasks[i].title.trimmingCharacters(in: .whitespacesAndNewlines)
            if lib.tasks[i].title.isEmpty { lib.tasks[i].title = "Untitled" }
        }
    }

    func setDone(_ id: UUID, _ done: Bool) {
        update(id) { $0.doneAt = done ? self.clock() : nil }
        if done, library.focus?.taskID == id { stopFocus() }
    }

    /// Gives a task a block at `start` (snapped to 15 minutes, or to the minute with `snap: false`). Refused when the block would
    /// already be over, since it would go straight back to the list.
    @discardableResult
    func schedule(_ id: UUID, at start: Date, snap: Bool = true) -> Bool {
        guard let task = library.task(id), !task.isDone else { return false }
        let snapped = snap ? planner.snap(start) : minute(of: start)
        guard planner.canSchedule(start: snapped, minutes: task.minutes, now: clock()) else {
            NSSound.beep()
            return false
        }
        update(id) { $0.start = snapped }
        return true
    }

    func unschedule(_ id: UUID) {
        update(id) { $0.start = nil }
    }

    func resize(_ id: UUID, minutes: Int) {
        update(id) { $0.minutes = max(15, minutes) }
    }

    func delete(_ id: UUID) {
        if let task = library.task(id), let eventID = task.copiedEventID {
            do { try service.removeCopy(eventID: eventID, taskID: id) } catch {
                log.error("copied block not removed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if library.focus?.taskID == id { stopFocus() }
        mutate { $0.tasks.removeAll { $0.id == id } }
    }

    // MARK: - Lists

    static let palette = ["#5b5fe6", "#e0662b", "#2fa36b", "#a35bd9", "#e0435c", "#d9a400", "#1f9bcf", "#8e8e93"]

    func addList(named name: String) -> UUID {
        let used = Set(library.lists.map(\.colorHex))
        let color = Self.palette.first { !used.contains($0) } ?? Self.palette[library.lists.count % Self.palette.count]
        let list = TaskList(name: name.isEmpty ? "New List" : name, colorHex: color)
        mutate { $0.lists.append(list) }
        return list.id
    }

    func updateList(_ id: UUID, _ change: (inout TaskList) -> Void) {
        mutate { lib in
            guard let i = lib.lists.firstIndex(where: { $0.id == id }) else { return }
            change(&lib.lists[i])
            if lib.lists[i].name.trimmingCharacters(in: .whitespaces).isEmpty { lib.lists[i].name = "Untitled" }
        }
    }

    /// Deletes a list; its tasks stay, without a list.
    func deleteList(_ id: UUID) {
        if selection == .list(id) { selection = .today }
        mutate { lib in
            lib.lists.removeAll { $0.id == id }
            for i in lib.tasks.indices where lib.tasks[i].listID == id { lib.tasks[i].listID = nil }
        }
    }

    // MARK: - Focus

    /// The Focus button: stops a running session, or starts one on the block happening now
    /// (or, with no block now, on the first unscheduled task, given a block from now).
    func toggleFocus() {
        let t = clock()
        if planner.active(library.focus, tasks: library.tasks, now: t) != nil {
            // Stopped by hand: no focus block happening now may start itself again.
            let happening = library.tasks.filter { $0.isFocusBlock && !$0.isDone && $0.covers(t) }.map(\.id)
            mutate { $0.skippedFocusTaskIDs.formUnion(happening) }
            stopFocus()
            return
        }
        switch planner.focusTarget(library.tasks, now: t) {
        case .current(let id)?:
            startFocus(id)
        case .startNow(let id)?:
            update(id) { $0.start = self.minute(of: t) }
            startFocus(id)
        case nil:
            NSSound.beep()
        }
    }

    var canFocus: Bool {
        planner.active(library.focus, tasks: library.tasks, now: clock()) != nil
            || planner.focusTarget(library.tasks, now: clock()) != nil
    }

    private func startFocus(_ id: UUID) {
        mutate { lib in
            lib.focus = Focus(taskID: id, startedAt: self.clock())
            lib.skippedFocusTaskIDs.remove(id)
        }
        runShortcut(library.settings.focusOnShortcut)
    }

    private func stopFocus() {
        mutate { $0.focus = nil }
        runShortcut(library.settings.focusOffShortcut)
    }

    // MARK: - Settings

    func updateSettings(_ change: (inout Preferences) -> Void) {
        mutate { lib in
            change(&lib.settings)
            (lib.settings.dayStartHour, lib.settings.dayEndHour) = Preferences.clampHours(
                lib.settings.dayStartHour, lib.settings.dayEndHour)
        }
    }

    // MARK: - Saving and copying

    private func mutate(_ change: (inout Library) -> Void) {
        var copy = library
        change(&copy)
        guard copy != library else { return }
        library = copy
        scheduleSave()
        scheduleCopySync()
    }

    private func scheduleSave() {
        guard store != nil, storeProblem == nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the library now (also called when the app quits).
    func saveNow() {
        guard let store, storeProblem == nil else { return }
        saveTask?.cancel()
        do {
            try store.save(library)
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
            notice = "SparkPlug couldn't save your tasks: \(error.localizedDescription)"
        }
    }

    private func scheduleCopySync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.syncCopies()
        }
    }

    /// Brings the copies of blocks in the chosen calendar in line with the open tasks: each open
    /// task with a block has a copy; one without a block (or with copying off) has none. Copies
    /// of finished tasks stay, as a record of the time spent.
    func syncCopies() {
        guard access == .granted else { return }
        var target: String?
        if let id = library.settings.copyCalendarID {
            // A chosen calendar that is missing for now (an account still syncing) or read-only:
            // leave every copy as it is rather than removing them all.
            guard calendars.contains(where: { $0.id == id && $0.allowsModifications }) else { return }
            target = id
        }
        var ids: [UUID: String?] = [:]
        for t in library.tasks where !t.isDone {
            do {
                if let target, t.start != nil {
                    let id = try service.upsertCopy(of: t, in: target)
                    if id != t.copiedEventID { ids[t.id] = .some(id) }
                } else if let eventID = t.copiedEventID {
                    try service.removeCopy(eventID: eventID, taskID: t.id)
                    ids[t.id] = .some(nil)
                }
            } catch {
                log.error("copy of \(t.id, privacy: .public) not synced: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard !ids.isEmpty else { return }
        mutate { lib in
            for i in lib.tasks.indices {
                if let id = ids[lib.tasks[i].id] { lib.tasks[i].copiedEventID = id }
            }
        }
    }

    // MARK: - What the views show

    var title: String {
        switch selection {
        case .today: return "Today"
        case .week: return "This Week"
        case .list(let id): return library.list(id)?.name ?? "List"
        }
    }

    var subtitle: String {
        switch selection {
        case .today:
            return format.dayTitle(now)
        case .week:
            let days = planner.week(containing: now, weekends: library.settings.showWeekends)
            return format.weekTitle(from: days.first ?? now, to: days.last ?? now)
        case .list(let id):
            let n = planner.openCounts(library.tasks)[id] ?? 0
            return n == 1 ? "1 open task" : "\(n) open tasks"
        }
    }

    /// The task list's groups for the current section and search. Today leaves out later days'
    /// blocks (the week shows those); a list shows everything in it.
    var taskGroups: [TaskGroup] {
        var listID: UUID?
        if case .list(let id) = selection { listID = id }
        let tasks = planner.filter(library.tasks, listID: listID, search: search, lists: library.lists)
        let groups = planner.groups(tasks, now: now)
        return listID == nil ? groups.filter { $0.kind != .later } : groups
    }

    var plannedSummary: String { planner.plannedSummary(library.tasks, now: now) }

    func listColorHex(_ id: UUID?) -> String { library.list(id)?.colorHex ?? "#8e8e93" }

    func activeFocus(at date: Date) -> ActiveFocus? {
        planner.active(library.focus, tasks: library.tasks, now: date)
    }

    func items(on day: Date) -> (timed: [TimelineItem], allDay: [TimelineItem]) {
        planner.items(
            on: day, tasks: library.tasks, events: events, hidden: library.settings.hiddenCalendarIDs,
            activeFocus: activeFocus(at: clock())?.task.id)
    }

    var minimumHours: (Int, Int) { (library.settings.dayStartHour, library.settings.dayEndHour) }
}
