import AppKit
import EventKit
import SparkPlugCore
import os

private let log = Logger(subsystem: "io.sprkplg.SparkPlug", category: "calendar")

/// `CalendarService` over EventKit: the calendars from every account added to this Mac.
@MainActor
final class EventKitCalendarService: CalendarService {
    private var store = EKEventStore()
    private var observer: NSObjectProtocol?

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied  // denied, restricted, or write-only (which cannot read events)
        }
    }

    func requestAccess() async -> CalendarAccess {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            log.error("calendar access request failed: \(error.localizedDescription, privacy: .public)")
        }
        // A store made before access was granted does not see the calendars; start a new one.
        if access == .granted { store = EKEventStore() }
        return access
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { c in
                CalendarInfo(
                    id: c.calendarIdentifier, title: c.title, source: c.source?.title ?? "",
                    colorHex: Self.hex(c.color), allowsModifications: c.allowsContentModifications)
            }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { e in
            guard let s = e.startDate, let en = e.endDate, let cal = e.calendar else { return nil }
            // A repeating event shares one identifier across occurrences; the start tells them apart.
            let id = "\(e.eventIdentifier ?? e.calendarItemIdentifier)@\(Int(s.timeIntervalSince1970))"
            return CalendarEvent(
                id: id, title: e.title ?? "", start: s, end: en, isAllDay: e.isAllDay,
                calendarID: cal.calendarIdentifier, taskID: Self.taskID(of: e), eventID: e.eventIdentifier)
        }
    }

    func upsertCopy(of task: TaskItem, in calendarID: String) throws -> String {
        guard let start = task.start, let end = task.end else { throw CopyError.notScheduled }
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            throw CopyError.noCalendar
        }
        let event = existingCopy(of: task) ?? EKEvent(eventStore: store)
        // Some accounts (Google, Exchange) drop or rewrite the URL and notes when they sync, so
        // the markers are written when the copy is made or has lost both — never compared, or
        // every server sync would rewrite the copy and set off another one.
        let marked = Self.taskID(of: event) == task.id
        let changed =
            !marked || event.title != task.title || event.startDate != start || event.endDate != end
            || event.calendar?.calendarIdentifier != calendarID
        if changed {
            event.title = task.title
            event.startDate = start
            event.endDate = end
            event.calendar = calendar
            if !marked {
                event.url = BlockURL.url(for: task.id)
                event.notes = BlockURL.url(for: task.id).absoluteString
            }
            event.availability = .busy
            try store.save(event, span: .thisEvent, commit: true)
        }
        guard let id = event.eventIdentifier else { throw CopyError.noIdentifier }
        return id
    }

    func removeCopy(eventID: String, taskID: UUID) throws {
        let probe = TaskItem(id: taskID, title: "", copiedEventID: eventID)
        guard let event = existingCopy(of: probe) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func onChange(_ handler: @escaping @MainActor () -> Void) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    /// The copy of `task` SparkPlug made before: the event with its saved id (SparkPlug made it,
    /// and only SparkPlug's own events are ever saved there), or — since some accounts change ids
    /// when they sync — an event near the block's time carrying the task's `sparkplug://task/<id>`
    /// marker. Nothing else is ever returned, so nothing else is ever changed or removed.
    private func existingCopy(of task: TaskItem) -> EKEvent? {
        if let id = task.copiedEventID, let e = store.event(withIdentifier: id), Self.taskID(of: e) ?? task.id == task.id {
            return e
        }
        let around = task.start ?? Date()
        let predicate = store.predicateForEvents(
            withStart: around.addingTimeInterval(-14 * 86400), end: around.addingTimeInterval(14 * 86400), calendars: nil)
        return store.events(matching: predicate).first { Self.taskID(of: $0) == task.id }
    }

    /// The task an event is a copy of, from its URL or the marker in its notes.
    static func taskID(of event: EKEvent) -> UUID? {
        if let id = BlockURL.taskID(from: event.url) { return id }
        guard let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return BlockURL.taskID(from: URL(string: notes))
    }

    enum CopyError: LocalizedError {
        case notScheduled, noCalendar, noIdentifier

        var errorDescription: String? {
            switch self {
            case .notScheduled: return "The task has no time."
            case .noCalendar: return "The calendar for copied blocks is missing or read-only."
            case .noIdentifier: return "The calendar did not return an id for the copied block."
            }
        }
    }

    static func hex(_ color: NSColor?) -> String {
        guard let c = color?.usingColorSpace(.sRGB) else { return "#8e8e93" }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
