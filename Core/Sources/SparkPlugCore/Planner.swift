import Foundation

/// A heading in the task list and the tasks under it.
public struct TaskGroup: Hashable, Identifiable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case scheduled, unscheduled, later, done
    }

    public var kind: Kind
    public var tasks: [TaskItem]

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .scheduled: return "Scheduled today"
        case .unscheduled: return "Unscheduled"
        case .later: return "Later"
        case .done: return "Done"
        }
    }
}

/// What the Focus button would do now.
public enum FocusTarget: Equatable, Sendable {
    /// Focus on the block that is happening now.
    case current(UUID)
    /// No block now: give this unscheduled task a block starting now and focus on it.
    case startNow(UUID)
}

/// A running focus session, worked out for a moment in time.
public struct ActiveFocus: Equatable, Sendable {
    public var task: TaskItem
    public var secondsLeft: Int
    /// 0 at the block's start, 1 at its end.
    public var progress: Double
}

/// SparkPlug's rules, as pure functions over the library.
public struct Planner: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    // MARK: - The task list

    /// Tasks in `listID` (all lists when nil) whose title or list name contains `search`.
    public func filter(_ tasks: [TaskItem], listID: UUID?, search: String, lists: [TaskList]) -> [TaskItem] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { t in
            if let listID, t.listID != listID { return false }
            guard !q.isEmpty else { return true }
            if t.title.localizedCaseInsensitiveContains(q) { return true }
            let name = lists.first { $0.id == t.listID }?.name ?? ""
            return name.localizedCaseInsensitiveContains(q)
        }
    }

    /// The task list's groups for `now`, empty groups left out:
    /// - Scheduled today: open, with a block today, by start time;
    /// - Unscheduled: open, with no block (or one on an earlier day), oldest first;
    /// - Later: open, with a block on a later day, by start time;
    /// - Done: finished today, most recent last.
    public func groups(_ tasks: [TaskItem], now: Date) -> [TaskGroup] {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var scheduled: [TaskItem] = [], unscheduled: [TaskItem] = [], later: [TaskItem] = [], done: [TaskItem] = []
        for t in tasks {
            if let doneAt = t.doneAt {
                if doneAt >= today && doneAt < tomorrow { done.append(t) }
            } else if let start = t.start, start >= today {
                if start < tomorrow { scheduled.append(t) } else { later.append(t) }
            } else {
                unscheduled.append(t)
            }
        }
        let byStart: (TaskItem, TaskItem) -> Bool = { a, b in
            a.start! != b.start! ? a.start! < b.start! : a.createdAt < b.createdAt
        }
        let result = [
            TaskGroup(kind: .scheduled, tasks: scheduled.sorted(by: byStart)),
            TaskGroup(kind: .unscheduled, tasks: unscheduled.sorted { $0.createdAt < $1.createdAt }),
            TaskGroup(kind: .later, tasks: later.sorted(by: byStart)),
            TaskGroup(kind: .done, tasks: done.sorted { $0.doneAt! < $1.doneAt! }),
        ]
        return result.filter { !$0.tasks.isEmpty }
    }

    /// "2h 15m planned · 3 blocks" for today's open blocks.
    public func plannedSummary(_ tasks: [TaskItem], now: Date) -> String {
        let scheduled = groups(tasks, now: now).first { $0.kind == .scheduled }?.tasks ?? []
        guard !scheduled.isEmpty else { return "Nothing planned" }
        let minutes = scheduled.reduce(0) { $0 + $1.minutes }
        let blocks = scheduled.count == 1 ? "1 block" : "\(scheduled.count) blocks"
        return "\(TimeFormat.duration(minutes: minutes)) planned · \(blocks)"
    }

    /// The Today count: open tasks with a block today or no block at all.
    public func todayCount(_ tasks: [TaskItem], now: Date) -> Int {
        groups(tasks, now: now).filter { $0.kind == .scheduled || $0.kind == .unscheduled }
            .reduce(0) { $0 + $1.tasks.count }
    }

    /// Open tasks per list.
    public func openCounts(_ tasks: [TaskItem]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for t in tasks where !t.isDone {
            if let l = t.listID { counts[l, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - Blocks

    /// Blocks whose time is over while their task is still open. These go back to the list.
    public func expired(_ tasks: [TaskItem], now: Date) -> [UUID] {
        tasks.filter { !$0.isDone && ($0.end.map { $0 <= now } ?? false) }.map(\.id)
    }

    /// A block can only be put where it has not already ended.
    public func canSchedule(start: Date, minutes: Int, now: Date) -> Bool {
        start.addingTimeInterval(TimeInterval(minutes * 60)) > now
    }

    /// `date` rounded to the nearest `minutes`.
    public func snap(_ date: Date, minutes: Int = 15) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = date.timeIntervalSince(day) / 60
        let snapped = (offset / Double(minutes)).rounded() * Double(minutes)
        return day.addingTimeInterval(snapped * 60)
    }

    // MARK: - Focus

    /// What the Focus button does now: the block covering now (a focus block first, then the
    /// earliest), else the first unscheduled task, else nothing.
    public func focusTarget(_ tasks: [TaskItem], now: Date) -> FocusTarget? {
        let current = tasks.filter { !$0.isDone && $0.covers(now) }
            .sorted { a, b in a.isFocusBlock != b.isFocusBlock ? a.isFocusBlock : a.start! < b.start! }
        if let t = current.first { return .current(t.id) }
        let unscheduled = groups(tasks, now: now).first { $0.kind == .unscheduled }?.tasks ?? []
        return unscheduled.first.map { .startNow($0.id) }
    }

    /// The focus block that should start by itself now, if any: an open focus block covering
    /// now that the person has not stopped by hand.
    public func autoFocus(_ tasks: [TaskItem], now: Date, skipped: Set<UUID>) -> UUID? {
        tasks.filter { $0.isFocusBlock && !$0.isDone && $0.covers(now) && !skipped.contains($0.id) }
            .min { $0.start! < $1.start! }?.id
    }

    /// The running session at `now`, or nil once its task is done, gone, or outside its block.
    public func active(_ focus: Focus?, tasks: [TaskItem], now: Date) -> ActiveFocus? {
        guard let focus, let task = tasks.first(where: { $0.id == focus.taskID }), !task.isDone,
            task.covers(now), let start = task.start, let end = task.end
        else { return nil }
        let total = end.timeIntervalSince(start)
        let left = end.timeIntervalSince(now)
        return ActiveFocus(task: task, secondsLeft: Int(left.rounded(.up)), progress: 1 - left / total)
    }

    // MARK: - Timeline

    /// The items for `day`: timed ones and all-day ones. Events on hidden calendars are left out,
    /// and so are SparkPlug's own copies of blocks it still has (the block itself is shown),
    /// recognised by their marker or by the event id saved with the task.
    public func items(
        on day: Date, tasks: [TaskItem], events: [CalendarEvent], hidden: Set<String>, activeFocus: UUID?
    ) -> (timed: [TimelineItem], allDay: [TimelineItem]) {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? day
        let known = Set(tasks.map(\.id))
        let copies = Set(tasks.compactMap(\.copiedEventID))
        var timed: [TimelineItem] = [], allDay: [TimelineItem] = []
        for e in events where e.start < dayEnd && e.end > dayStart && !hidden.contains(e.calendarID) {
            if let t = e.taskID, known.contains(t) { continue }
            if let id = e.eventID, copies.contains(id) { continue }
            let item = TimelineItem(
                id: "e:" + e.id, kind: .event(calendarID: e.calendarID), title: e.title, start: e.start, end: e.end)
            if e.isAllDay { allDay.append(item) } else { timed.append(item) }
        }
        for t in tasks {
            guard let start = t.start, let end = t.end, start < dayEnd, end > dayStart else { continue }
            timed.append(
                TimelineItem(
                    id: "t:" + t.id.uuidString, kind: .task(t.id), title: t.title, start: start, end: end,
                    isDone: t.isDone, isFocus: t.isFocusBlock || t.id == activeFocus, isActiveFocus: t.id == activeFocus
                ))
        }
        return (timed, allDay)
    }

    /// The days of the week containing `date`: Monday to Friday, or to Sunday with weekends.
    public func week(containing date: Date, weekends: Bool) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)  // 1 = Sunday
        let fromMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -fromMonday, to: day) else { return [day] }
        return (0..<(weekends ? 7 : 5)).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Open tasks due on `day`, oldest first.
    public func due(on day: Date, _ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { t in !t.isDone && (t.due.map { calendar.isDate($0, inSameDayAs: day) } ?? false) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Quick entry

    /// Splits a length off the end of a typed title: "Renew passport 20m" → ("Renew passport", 20).
    /// Understands `20m`, `20 min`, `1h`, `1.5h`, `1h30m` and `1h 30m`.
    public static func parseQuickEntry(_ text: String) -> (title: String, minutes: Int?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = /\s+(?:(\d{1,2}(?:\.\d{1,2})?)\s*(?:h|hr|hrs|hours?))?\s*(?:(\d{1,4})\s*(?:m|min|mins|minutes?))?$/
            .ignoresCase()
        guard let match = trimmed.firstMatch(of: pattern), match.1 != nil || match.2 != nil else {
            return (trimmed, nil)
        }
        let hours = match.1.flatMap { Double($0) } ?? 0
        let mins = match.2.flatMap { Int($0) } ?? 0
        let total = Int((hours * 60).rounded()) + mins
        let title = String(trimmed[..<match.range.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard total > 0, total <= 24 * 60, !title.isEmpty else { return (trimmed, nil) }
        return (title, total)
    }

    /// The lengths offered when giving a task its rough length.
    public static let lengths = [10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
}
