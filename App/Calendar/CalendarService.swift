import Foundation
import SparkPlugCore

/// Whether SparkPlug may read the Mac's calendars.
enum CalendarAccess: Equatable {
    case notDetermined
    case granted
    /// Denied or restricted: the person has to change it in System Settings.
    case denied
}

/// The calendars on this Mac. SparkPlug reads events from them and, when the person chooses a
/// calendar in Settings, writes copies of its blocks there — nothing else.
@MainActor
protocol CalendarService: AnyObject {
    var access: CalendarAccess { get }
    func requestAccess() async -> CalendarAccess
    func calendars() -> [CalendarInfo]
    func events(from start: Date, to end: Date) -> [CalendarEvent]
    /// Creates or updates the copy of `task`'s block in `calendarID` and returns its event id.
    func upsertCopy(of task: TaskItem, in calendarID: String) throws -> String
    /// Deletes a copy made by `upsertCopy`. A copy that is already gone is not an error.
    func removeCopy(eventID: String, taskID: UUID) throws
    /// Calls `handler` whenever the calendars change (here or in another app).
    func onChange(_ handler: @escaping @MainActor () -> Void)
}
