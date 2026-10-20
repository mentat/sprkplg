import SparkPlugCore
import SwiftUI

/// Today and This Week, the lists, and the Mac's calendars (click one to hide or show it).
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: UUID?
    @State private var draftName = ""
    @State private var deleting: TaskList?
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var model = model
        let counts = model.planner.openCounts(model.library.tasks)
        List(selection: $model.selection) {
            NavRow(
                title: "Today", systemImage: "sun.max", selected: model.selection == .today,
                count: model.planner.todayCount(model.library.tasks, now: model.now)
            )
            .tag(AppModel.Section.today)
            NavRow(title: "This Week", systemImage: "calendar", selected: model.selection == .week, count: nil)
                .tag(AppModel.Section.week)

            Section("Lists") {
                ForEach(model.library.lists) { list in
                    listRow(list, count: counts[list.id] ?? 0)
                        .tag(AppModel.Section.list(list.id))
                }
            }

            Section("Calendars") {
                if model.access == .granted {
                    ForEach(model.calendars) { cal in
                        CalendarRow(calendar: cal, shown: !model.isHidden(cal.id)) { model.toggleCalendar(cal.id) }
                    }
                } else if model.access == .notDetermined {
                    Button("Show Your Calendars…") {
                        Task { await model.requestCalendarAccess() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                } else {
                    Button("Turn On Calendar Access…") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    let id = model.addList(named: "New List")
                    draftName = "New List"
                    renaming = id
                    nameFocused = true
                } label: {
                    Label("New List", systemImage: "plus.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .confirmationDialog(
            "Delete the list “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { list in
            Button("Delete List", role: .destructive) { model.deleteList(list.id) }
        } message: { _ in
            Text("Its tasks stay, without a list.")
        }
    }

    @ViewBuilder
    private func listRow(_ list: TaskList, count: Int) -> some View {
        HStack(spacing: 9) {
            Circle().fill(Color(hex: list.colorHex)).frame(width: 10, height: 10).padding(.horizontal, 3)
            if renaming == list.id {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit { commitRename(list.id) }
                    .onExitCommand { renaming = nil }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename(list.id) } }
            } else {
                Text(list.name).lineLimit(1)
            }
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)").font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
            }
        }
        .font(.system(size: 13))
        .contextMenu {
            Button("Rename") {
                draftName = list.name
                renaming = list.id
                nameFocused = true
            }
            Menu("Color") {
                ForEach(Array(zip(AppModel.palette, Self.colorNames)), id: \.0) { hex, name in
                    Toggle(name, isOn: Binding(get: { list.colorHex == hex }, set: { _ in model.updateList(list.id) { $0.colorHex = hex } }))
                }
            }
            Divider()
            Button("Delete List…", role: .destructive) { deleting = list }
        }
    }

    private static let colorNames = ["Indigo", "Orange", "Green", "Purple", "Red", "Yellow", "Blue", "Gray"]

    private func commitRename(_ id: UUID) {
        guard renaming == id else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { model.updateList(id) { $0.name = name } }
        renaming = nil
    }
}

private struct NavRow: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let count: Int?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Theme.accent : Color.primary.opacity(0.8))
                .frame(width: 18)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 4)
            if let count, count > 0 {
                Text("\(count)").font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
            }
        }
    }
}

private struct CalendarRow: View {
    let calendar: CalendarInfo
    let shown: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shown ? Color(hex: calendar.colorHex) : .clear)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(hex: calendar.colorHex), lineWidth: shown ? 0 : 1.5)
                    if shown {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.horizontal, 1)
                Text(calendar.title).lineLimit(1).foregroundStyle(shown ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shown ? "Hide \(calendar.title) (\(calendar.source))" : "Show \(calendar.title) (\(calendar.source))")
    }
}
