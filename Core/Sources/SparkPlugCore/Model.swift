import Foundation

/// A list that tasks belong to ("Work", "Errands", …).
public struct TaskList: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// sRGB colour as `#rrggbb`.
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// A to-do. A task with a `start` is a block on the calendar; one without sits in the list.
public struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var listID: UUID?
    /// The rough length the person gave it.
    public var minutes: Int
    /// When its block starts, if it has been given a time.
    public var start: Date?
    /// The day it is due, if any (any time on that day).
    public var due: Date?
    /// A focus block starts Focus by itself when it begins.
    public var isFocusBlock: Bool
    public var doneAt: Date?
    public var createdAt: Date
    /// The event this block was copied to, when blocks are copied to a calendar.
    public var copiedEventID: String?

    public init(
        id: UUID = UUID(), title: String, listID: UUID? = nil, minutes: Int = 30, start: Date? = nil,
        due: Date? = nil, isFocusBlock: Bool = false, doneAt: Date? = nil, createdAt: Date = Date(),
        copiedEventID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.listID = listID
        self.minutes = minutes
        self.start = start
        self.due = due
        self.isFocusBlock = isFocusBlock
        self.doneAt = doneAt
        self.createdAt = createdAt
        self.copiedEventID = copiedEventID
    }

    public var isDone: Bool { doneAt != nil }

    /// When its block ends.
    public var end: Date? { start.map { $0.addingTimeInterval(TimeInterval(minutes * 60)) } }

    /// True while `date` falls inside the block.
    public func covers(_ date: Date) -> Bool {
        guard let start, let end else { return false }
        return start <= date && date < end
    }

    enum CodingKeys: String, CodingKey {
        case id, title, listID, minutes, start, due, isFocusBlock, doneAt, createdAt, copiedEventID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        listID = try c.decodeIfPresent(UUID.self, forKey: .listID)
        minutes = max(5, try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 30)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        isFocusBlock = try c.decodeIfPresent(Bool.self, forKey: .isFocusBlock) ?? false
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        copiedEventID = try c.decodeIfPresent(String.self, forKey: .copiedEventID)
    }
}

/// Preferences, kept with the tasks so the whole app state is one file.
public struct Preferences: Codable, Equatable, Sendable {
    /// The timeline always shows at least these hours (it widens to fit the day's items).
    public var dayStartHour: Int
    public var dayEndHour: Int
    public var showWeekends: Bool
    /// The calendar blocks are copied to; nil keeps them in SparkPlug only.
    public var copyCalendarID: String?
    /// Shortcuts run when Focus starts and ends (to turn Do Not Disturb on and off).
    public var focusOnShortcut: String?
    public var focusOffShortcut: String?
    public var hiddenCalendarIDs: Set<String>

    public init(
        dayStartHour: Int = 8, dayEndHour: Int = 18, showWeekends: Bool = false, copyCalendarID: String? = nil,
        focusOnShortcut: String? = nil, focusOffShortcut: String? = nil, hiddenCalendarIDs: Set<String> = []
    ) {
        self.dayStartHour = dayStartHour
        self.dayEndHour = dayEndHour
        self.showWeekends = showWeekends
        self.copyCalendarID = copyCalendarID
        self.focusOnShortcut = focusOnShortcut
        self.focusOffShortcut = focusOffShortcut
        self.hiddenCalendarIDs = hiddenCalendarIDs
    }

    enum CodingKeys: String, CodingKey {
        case dayStartHour, dayEndHour, showWeekends, copyCalendarID, focusOnShortcut, focusOffShortcut, hiddenCalendarIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        let start = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? d.dayStartHour
        let end = try c.decodeIfPresent(Int.self, forKey: .dayEndHour) ?? d.dayEndHour
        (dayStartHour, dayEndHour) = Preferences.clampHours(start, end)
        showWeekends = try c.decodeIfPresent(Bool.self, forKey: .showWeekends) ?? d.showWeekends
        copyCalendarID = try c.decodeIfPresent(String.self, forKey: .copyCalendarID)
        focusOnShortcut = try c.decodeIfPresent(String.self, forKey: .focusOnShortcut)
        focusOffShortcut = try c.decodeIfPresent(String.self, forKey: .focusOffShortcut)
        hiddenCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenCalendarIDs) ?? []
    }

    /// Keeps a start/end hour pair inside 0…24 with the end after the start.
    public static func clampHours(_ start: Int, _ end: Int) -> (Int, Int) {
        let s = min(max(start, 0), 23)
        return (s, min(max(end, s + 1), 24))
    }
}

/// A running focus session.
public struct Focus: Codable, Equatable, Sendable {
    public var taskID: UUID
    public var startedAt: Date

    public init(taskID: UUID, startedAt: Date) {
        self.taskID = taskID
        self.startedAt = startedAt
    }
}

/// Everything SparkPlug keeps: lists, tasks, settings and the focus session.
public struct Library: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var lists: [TaskList]
    public var tasks: [TaskItem]
    public var settings: Preferences
    public var focus: Focus?
    /// Focus blocks the person stopped by hand while they were running, so they do not start
    /// themselves again (dropped once the block is no longer happening).
    public var skippedFocusTaskIDs: Set<UUID>

    public init(
        lists: [TaskList] = [], tasks: [TaskItem] = [], settings: Preferences = Preferences(), focus: Focus? = nil,
        skippedFocusTaskIDs: Set<UUID> = []
    ) {
        self.version = Library.currentVersion
        self.lists = lists
        self.tasks = tasks
        self.settings = settings
        self.focus = focus
        self.skippedFocusTaskIDs = skippedFocusTaskIDs
    }

    /// What a first launch starts with: four empty lists.
    public static func starter() -> Library {
        Library(lists: [
            TaskList(name: "Work", colorHex: "#5b5fe6"),
            TaskList(name: "Home", colorHex: "#e0662b"),
            TaskList(name: "Personal", colorHex: "#2fa36b"),
            TaskList(name: "Errands", colorHex: "#a35bd9"),
        ])
    }

    enum CodingKeys: String, CodingKey {
        case version, lists, tasks, settings, focus, skippedFocusTaskIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version <= Library.currentVersion else {
            throw LibraryError.newerVersion(version)
        }
        lists = try c.decodeIfPresent([TaskList].self, forKey: .lists) ?? []
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        settings = try c.decodeIfPresent(Preferences.self, forKey: .settings) ?? Preferences()
        focus = try c.decodeIfPresent(Focus.self, forKey: .focus)
        skippedFocusTaskIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .skippedFocusTaskIDs) ?? []
        version = Library.currentVersion
    }

    public func list(_ id: UUID?) -> TaskList? {
        guard let id else { return nil }
        return lists.first { $0.id == id }
    }

    public func task(_ id: UUID) -> TaskItem? {
        tasks.first { $0.id == id }
    }
}

public enum LibraryError: Error, Equatable, CustomStringConvertible {
    /// The file was written by a newer SparkPlug; it is left alone.
    case newerVersion(Int)

    public var description: String {
        switch self {
        case .newerVersion(let v):
            return "The library was saved by a newer version of SparkPlug (format \(v)). Update SparkPlug to open it."
        }
    }
}

/// A calendar on this Mac, as SparkPlug sees it.
public struct CalendarInfo: Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// The account it belongs to ("iCloud", "Google", "Exchange", "On My Mac").
    public var source: String
    public var colorHex: String
    public var allowsModifications: Bool

    public init(id: String, title: String, source: String, colorHex: String, allowsModifications: Bool) {
        self.id = id
        self.title = title
        self.source = source
        self.colorHex = colorHex
        self.allowsModifications = allowsModifications
    }
}

/// One occurrence of a calendar event.
public struct CalendarEvent: Hashable, Identifiable, Sendable {
    /// Unique per occurrence (a repeating event has one per day).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    /// Set when this event is SparkPlug's own copy of a block.
    public var taskID: UUID?
    /// The calendar's own id for the event (shared by a repeating event's occurrences).
    public var eventID: String?

    public init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, calendarID: String,
        taskID: UUID? = nil, eventID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.taskID = taskID
        self.eventID = eventID
    }
}

/// The URL SparkPlug puts on the events it copies blocks to, so it can recognise them.
public enum BlockURL {
    public static let scheme = "sparkplug"

    public static func url(for taskID: UUID) -> URL {
        URL(string: "\(scheme)://task/\(taskID.uuidString)")!
    }

    public static func taskID(from url: URL?) -> UUID? {
        guard let url, url.scheme == scheme, url.host == "task" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
