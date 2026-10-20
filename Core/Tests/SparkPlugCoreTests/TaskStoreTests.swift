import Foundation
import Testing
@testable import SparkPlugCore

@Suite struct TaskStoreTests {
    let dir: URL
    let store: TaskStore

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sparkplug-tests-\(UUID().uuidString)")
        store = TaskStore(url: dir.appendingPathComponent("nested/library.json"))
    }

    @Test func firstLaunchStartsWithTheFourLists() throws {
        let result = try store.load()
        guard case .fresh(let library) = result else { Issue.record("expected fresh, got \(result)"); return }
        #expect(library.lists.map(\.name) == ["Work", "Home", "Personal", "Errands"])
        #expect(library.tasks.isEmpty)
    }

    @Test func roundTripsEverything() throws {
        var library = Library.starter()
        let list = library.lists[0].id
        let t = TaskItem(
            title: "Draft Q4 roadmap", listID: list, minutes: 90, start: oct20(9.5), due: oct20(0, day: 23),
            isFocusBlock: true, doneAt: nil, createdAt: oct20(8), copiedEventID: "EV1")
        library.tasks = [t, TaskItem(title: "Done", doneAt: oct20(8.25), createdAt: oct20(7))]
        library.settings = Preferences(
            dayStartHour: 7, dayEndHour: 20, showWeekends: true, copyCalendarID: "cal", focusOnShortcut: "DND On",
            focusOffShortcut: "DND Off", hiddenCalendarIDs: ["x", "y"])
        library.focus = Focus(taskID: t.id, startedAt: oct20(9.5))
        library.skippedFocusTaskIDs = [t.id]
        try store.save(library)
        #expect(try store.load() == .loaded(library))
    }

    @Test func olderFilesWithMissingFieldsGetDefaults() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let id = UUID()
        let json = """
            {"version":1,"tasks":[{"id":"\(id.uuidString)","title":"Bare","minutes":2}],"settings":{"dayStartHour":30}}
            """
        try json.write(to: store.url, atomically: true, encoding: .utf8)
        let library = try store.load().library
        #expect(library.lists.isEmpty)
        #expect(library.tasks.first?.minutes == 5)  // lengths below 5 minutes are raised
        #expect(library.tasks.first?.isFocusBlock == false)
        #expect(library.settings.dayStartHour == 23 && library.settings.dayEndHour == 24)
        #expect(!library.settings.showWeekends)
    }

    @Test func unreadableFilesAreMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.url)
        let result = try store.load(now: Date(timeIntervalSince1970: 0))
        guard case .recovered(let library, let aside) = result else { Issue.record("expected recovered"); return }
        #expect(library.lists.count == 4)
        #expect(aside.lastPathComponent == "library.unreadable-19700101-000000.json")
        #expect(try String(contentsOf: aside, encoding: .utf8) == "{ not json")
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func filesFromANewerVersionAreRefusedAndKept() throws {
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":99,"tasks":[]}"#.utf8).write(to: store.url)
        #expect(throws: LibraryError.newerVersion(99)) { try store.load() }
        #expect(FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func blockURLsRoundTrip() {
        let id = UUID()
        #expect(BlockURL.taskID(from: BlockURL.url(for: id)) == id)
        #expect(BlockURL.taskID(from: URL(string: "https://example.com/task/\(id)")) == nil)
        #expect(BlockURL.taskID(from: URL(string: "sparkplug://task/not-a-uuid")) == nil)
        #expect(BlockURL.taskID(from: nil) == nil)
    }

    @Test func taskCoversItsBlockHalfOpen() {
        let t = TaskItem(title: "t", minutes: 30, start: oct20(9))
        #expect(t.covers(oct20(9)))
        #expect(t.covers(oct20(9.49)))
        #expect(!t.covers(oct20(9.5)))
        #expect(!TaskItem(title: "u").covers(oct20(9)))
        #expect(t.end == oct20(9.5))
    }

    @Test func hourClamping() {
        #expect(Preferences.clampHours(8, 18) == (8, 18))
        #expect(Preferences.clampHours(-3, 30) == (0, 24))
        #expect(Preferences.clampHours(12, 10) == (12, 13))
    }
}
