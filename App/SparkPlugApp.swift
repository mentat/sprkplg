import AppKit
import SwiftUI

@main
struct SparkPlugApp: App {
    /// `--demo` opens the sample week instead of your calendars and tasks (nothing is saved).
    /// `--week` opens on This Week.
    @State private var model: AppModel = {
        // Under the unit tests the app runs on the demo data, so tests never touch your tasks.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let m = AppModel(demo: testing || CommandLine.arguments.contains("--demo"))
        if CommandLine.arguments.contains("--week") { m.selection = .week }
        return m
    }()

    var body: some Scene {
        Window("SparkPlug", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { SparkPlugCommands(model: model) }

        Settings {
            SettingsView().environment(model)
        }
    }
}

struct SparkPlugCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { model.beginNewTask() }
                .keyboardShortcut("n")
        }
        CommandGroup(before: .toolbar) {
            Button("Day") { model.selection = .today }
                .keyboardShortcut("1")
            Button("Week") { model.selection = .week }
                .keyboardShortcut("2")
            Divider()
            Button("Start or Stop Focus") { model.toggleFocus() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
        }
    }
}

extension AppModel {
    /// Opens the quick-entry row (switching to the day, where the task list is).
    func beginNewTask() {
        if selection == .week { selection = .today }
        isAddingTask = true
    }
}
