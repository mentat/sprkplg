import Foundation
import SparkPlugCore

/// The sample week shown with `--demo`: a Tuesday at 10:40 AM, focusing on "Draft Q4 roadmap".
/// Nothing is read from or written to your calendars or your library in demo mode.
@MainActor
enum DemoData {
    static let calendars = [
        CalendarInfo(id: "demo-work", title: "Work", source: "Demo", colorHex: "#0a7cff", allowsModifications: true),
        CalendarInfo(id: "demo-personal", title: "Personal", source: "Demo", colorHex: "#2fb457", allowsModifications: true),
        CalendarInfo(id: "demo-family", title: "Family", source: "Demo", colorHex: "#ff8a00", allowsModifications: true),
    ]

    /// The Tuesday of this week at 10:40:12 — 19:48 left on the focus block, as in the design.
    static func now(calendar: Calendar = .current) -> Date {
        let tuesday = Planner(calendar: calendar).week(containing: Date(), weekends: false)[1]
        return tuesday.addingTimeInterval(10 * 3600 + 40 * 60 + 12)
    }

    private static func at(_ day: Int, _ hour: Double, calendar: Calendar) -> Date {
        let monday = Planner(calendar: calendar).week(containing: now(calendar: calendar), weekends: false)[0]
        let d = calendar.date(byAdding: .day, value: day, to: monday)!
        return d.addingTimeInterval(hour * 3600)
    }

    static func events(calendar: Calendar = .current) -> [CalendarEvent] {
        let rows: [(Int, String, Double, Double, String)] = [
            (0, "Standup", 9, 9.5, "work"), (0, "Client call", 14, 15, "work"), (0, "Gym", 17, 18, "personal"),
            (1, "Standup", 9, 9.5, "work"), (1, "Design review", 11.5, 12.5, "work"),
            (1, "Lunch with Maya", 12.5, 13.25, "personal"), (1, "Dentist", 15.25, 16, "family"),
            (1, "1:1 with Jordan", 17, 17.5, "work"),
            (2, "Standup", 9, 9.5, "work"), (2, "Product sync", 13, 14, "work"), (2, "Piano lesson", 16.5, 17.5, "family"),
            (3, "Standup", 9, 9.5, "work"), (3, "Interview", 10, 11, "work"), (3, "Lunch & learn", 12, 13, "work"),
            (4, "Standup", 9, 9.5, "work"), (4, "Roadmap review", 10, 11.5, "work"),
            (4, "Team drinks", 16.5, 18, "personal"),
            (5, "Kids' soccer", 10, 11, "family"), (6, "Brunch with parents", 11, 12.5, "family"),
        ]
        return rows.enumerated().map { i, r in
            CalendarEvent(
                id: "demo-\(i)", title: r.1, start: at(r.0, r.2, calendar: calendar), end: at(r.0, r.3, calendar: calendar),
                calendarID: "demo-" + r.4)
        }
    }

    static func library(calendar: Calendar = .current) -> Library {
        var lib = Library.starter()
        let (work, home, personal, errands) = (lib.lists[0].id, lib.lists[1].id, lib.lists[2].id, lib.lists[3].id)
        var order = 0.0
        func t(
            _ title: String, _ list: UUID, _ minutes: Int, day: Int = 1, at hour: Double? = nil, due: Int? = nil,
            focus: Bool = false, done: Bool = false
        ) -> TaskItem {
            order += 1
            return TaskItem(
                title: title, listID: list, minutes: minutes, start: hour.map { at(day, $0, calendar: calendar) },
                due: due.map { at($0, 0, calendar: calendar) }, isFocusBlock: focus,
                doneAt: done ? at(day, (hour ?? 8) + Double(minutes) / 60, calendar: calendar) : nil,
                createdAt: at(0, 0, calendar: calendar).addingTimeInterval(order))
        }
        let roadmap = t("Draft Q4 roadmap", work, 90, at: 9.5, focus: true)
        lib.tasks = [
            roadmap,
            t("Reply to contractor quotes", home, 60, at: 13.5),
            t("Review budget sheet", work, 30, at: 14.5),
            t("Pick up dry cleaning", errands, 45, at: 16.25),
            t("Renew passport", errands, 20, due: 1),
            t("Call the bank about the card", personal, 10),
            t("Plan Sam's birthday", personal, 60),
            t("Write onboarding copy", work, 120),
            t("Book flights for March", personal, 15, done: true),
            // The rest of the week.
            t("Write onboarding outline", work, 120, day: 0, at: 10, done: true),
            t("Finish Q4 roadmap", work, 120, day: 2, at: 9.5, focus: true),
            t("Expense report", work, 60, day: 2, at: 15, due: 2),
            t("Deck for Friday", work, 120, day: 3, at: 14, focus: true),
            t("Call the insurer", personal, 30, day: 3, at: 16.5),
            t("Pay rent", home, 60, day: 4, at: 13, due: 4),
            t("Garage clean-out", home, 120, day: 5, at: 12),
            t("Plan next week", personal, 45, day: 6, at: 16),
        ]
        lib.focus = Focus(taskID: roadmap.id, startedAt: roadmap.start!)
        return lib
    }
}

/// The demo's calendars: fixed, read-only, and never touching EventKit.
@MainActor
final class DemoCalendarService: CalendarService {
    var access: CalendarAccess { .granted }
    func requestAccess() async -> CalendarAccess { .granted }
    func calendars() -> [CalendarInfo] { DemoData.calendars }
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        DemoData.events().filter { $0.start < end && $0.end > start }
    }
    func upsertCopy(of task: TaskItem, in calendarID: String) throws -> String { "demo-copy-\(task.id)" }
    func removeCopy(eventID: String, taskID: UUID) throws {}
    func onChange(_ handler: @escaping @MainActor () -> Void) {}
}
