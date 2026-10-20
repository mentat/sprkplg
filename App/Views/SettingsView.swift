import SparkPlugCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CalendarSettings().tabItem { Label("Calendars", systemImage: "calendar") }
            FocusSettings().tabItem { Label("Focus", systemImage: "bolt") }
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.library.settings
        Form {
            Picker("Day starts at", selection: Binding(get: { s.dayStartHour }, set: { v in model.updateSettings { $0.dayStartHour = v } })) {
                ForEach(0..<24, id: \.self) { Text(model.format.hourLabel($0)).tag($0) }
            }
            Picker("Day ends at", selection: Binding(get: { s.dayEndHour }, set: { v in model.updateSettings { $0.dayEndHour = v } })) {
                ForEach((s.dayStartHour + 1)...24, id: \.self) { Text(model.format.hourLabel($0)).tag($0) }
            }
            Text("The timeline always shows these hours, and stretches to fit anything earlier or later.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show weekends in This Week", isOn: Binding(get: { s.showWeekends }, set: { v in model.updateSettings { $0.showWeekends = v } }))
            if !model.isDemo, let url = try? TaskStore.defaultURL() {
                LabeledContent("Your tasks") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Text("Saved on this Mac only, in \(url.deletingLastPathComponent().path).")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct CalendarSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let writable = model.calendars.filter(\.allowsModifications)
        Form {
            LabeledContent("Calendar access") {
                switch model.access {
                case .granted:
                    Text("Allowed").foregroundStyle(.secondary)
                case .notDetermined:
                    Button("Allow Access") { Task { await model.requestCalendarAccess() } }
                case .denied:
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
            }
            Picker(
                "Copy blocks to",
                selection: Binding(
                    get: { model.library.settings.copyCalendarID },
                    set: { v in model.updateSettings { $0.copyCalendarID = v } })
            ) {
                Text("Don't copy").tag(String?.none)
                ForEach(writable) { c in
                    Text("\(c.title) — \(c.source)").tag(String?.some(c.id))
                }
            }
            .disabled(model.access != .granted)
            Text(
                "Blocks stay in SparkPlug unless you choose a calendar. Copies are kept up to date as you move blocks, and removed when a task goes back to your list."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

private struct FocusSettings: View {
    @Environment(AppModel.self) private var model
    @State private var shortcuts: [String] = []

    var body: some View {
        Form {
            shortcutPicker("When Focus starts, run", \.focusOnShortcut)
            shortcutPicker("When Focus ends, run", \.focusOffShortcut)
            Text(
                "macOS doesn't let apps turn on Do Not Disturb themselves. In the Shortcuts app, make two shortcuts with the “Set Focus” action — one turning Do Not Disturb on, one turning it off — and choose them here."
            )
            .font(.caption).foregroundStyle(.secondary)
            Button("Open Shortcuts") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
        .task { shortcuts = await ShortcutRunner.list() }
    }

    private func shortcutPicker(_ label: String, _ key: WritableKeyPath<Preferences, String?>) -> some View {
        let current = model.library.settings[keyPath: key]
        var names = shortcuts
        if let current, !names.contains(current) { names.insert(current, at: 0) }
        return HStack {
            Picker(label, selection: Binding(get: { current }, set: { v in model.updateSettings { $0[keyPath: key] = v } })) {
                Text("Nothing").tag(String?.none)
                ForEach(names, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Button("Run") { ShortcutRunner.run(current) }
                .disabled(current == nil)
                .help("Run it now to check it works")
        }
    }
}
