import SparkPlugCore
import SwiftUI
import UniformTypeIdentifiers

/// The task list beside the day's timeline.
struct TaskColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = model.taskGroups
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Tasks").font(.system(size: 20, weight: .bold)).tracking(-0.2)
                    Spacer()
                    Text(model.plannedSummary).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 8).padding(.bottom, 8)

                if model.isAddingTask { NewTaskRow() }

                ForEach(groups) { group in
                    Text(group.title)
                        .font(.system(size: 11, weight: .bold)).tracking(0.22)
                        .foregroundStyle(Theme.sectionLabel)
                        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
                    ForEach(group.tasks) { task in
                        TaskRow(task: task)
                    }
                }

                if groups.isEmpty && !model.isAddingTask {
                    emptyState
                }
            }
            .padding(.vertical, 16).padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.search.isEmpty {
                Text("Nothing to do yet").font(.system(size: 13.5, weight: .semibold))
                Text("Add a task with ⌘N — give it a rough length, then drag it onto the timeline.")
            } else {
                Text("No tasks match “\(model.search)”").font(.system(size: 13.5, weight: .semibold))
            }
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 8).padding(.top, 12)
    }
}

/// One task: its ring, title, list and length, and its start time once it has a block.
struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    @State private var hovering = false
    @State private var editing = false

    var body: some View {
        let list = model.library.list(task.listID)
        HStack(alignment: .top, spacing: 10) {
            Button {
                model.setDone(task.id, !task.isDone)
            } label: {
                Ring(done: task.isDone)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help(task.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(task.isDone ? Theme.tertiary : Color.primary)
                    .strikethrough(task.isDone)
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: model.listColorHex(task.listID))).frame(width: 7, height: 7)
                    Text(list?.name ?? "No list")
                    Text("·")
                    Text(TimeFormat.duration(minutes: task.minutes))
                    if let due = task.due, !task.isDone {
                        Text("·")
                        Text("Due \(model.planner.calendar.isDateInToday(due) ? "today" : model.format.shortDate(due))")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            if task.isFocusBlock && !task.isDone {
                Bolt().fill(Theme.focusEdge).frame(width: 12, height: 12).padding(.top, 4)
                    .help("Focus block: Focus starts by itself when the block begins")
            }
            if let start = task.start, !task.isDone {
                Text(model.planner.calendar.isDate(start, inSameDayAs: model.now)
                    ? model.format.shortTime(start) : model.format.weekday(start).capitalized + " " + model.format.shortTime(start))
                    .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.chipInk)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.chipFill))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { editing = true }
        .popover(isPresented: $editing, arrowEdge: .trailing) { TaskEditor(taskID: task.id) }
        .onDrag {
            model.draggingTaskID = task.isDone ? nil : task.id
            let provider = NSItemProvider(object: task.title as NSString)
            let id = task.id.uuidString
            // A private type, seen only by SparkPlug's timeline: text dragged from elsewhere is never a task.
            provider.registerDataRepresentation(forTypeIdentifier: UTType.sparkplugTask.identifier, visibility: .ownProcess) {
                $0(Data(id.utf8), nil)
                return nil
            }
            return provider
        }
        .contextMenu { TaskMenu(task: task, edit: { editing = true }) }
    }
}

/// The actions shared by a task's row and its block.
struct TaskMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let edit: () -> Void

    var body: some View {
        Button("Edit…", action: edit)
        Button(task.isDone ? "Mark as Not Done" : "Mark as Done") { model.setDone(task.id, !task.isDone) }
        if !task.isDone {
            if task.start != nil {
                Button("Move Back to List") { model.unschedule(task.id) }
            } else {
                Button("Start Now") { model.schedule(task.id, at: model.clock(), snap: false) }
            }
        }
        Divider()
        Menu("Length") {
            ForEach(lengths, id: \.self) { m in
                Toggle(TimeFormat.duration(minutes: m), isOn: Binding(get: { task.minutes == m }, set: { _ in model.update(task.id) { $0.minutes = m } }))
            }
        }
        Menu("List") {
            ForEach(model.library.lists) { list in
                Toggle(list.name, isOn: Binding(get: { task.listID == list.id }, set: { _ in model.update(task.id) { $0.listID = list.id } }))
            }
        }
        Menu("Due") {
            Button("Today") { model.update(task.id) { $0.due = model.planner.calendar.startOfDay(for: model.now) } }
            Button("Tomorrow") {
                let cal = model.planner.calendar
                model.update(task.id) { $0.due = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: model.now)) }
            }
            if task.due != nil {
                Button("No Due Date") { model.update(task.id) { $0.due = nil } }
            }
        }
        Toggle("Focus Block", isOn: Binding(get: { task.isFocusBlock }, set: { v in model.update(task.id) { $0.isFocusBlock = v } }))
        Divider()
        Button("Delete", role: .destructive) { model.delete(task.id) }
    }

    private var lengths: [Int] {
        Planner.lengths.contains(task.minutes) ? Planner.lengths : (Planner.lengths + [task.minutes]).sorted()
    }
}

/// The quick-entry row: type a title (with an optional length like "20m" at the end), pick a
/// list and a length, press Return. Escape closes it.
struct NewTaskRow: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var listID: UUID?
    @State private var minutes = 30
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = Planner.parseQuickEntry(text)
        let list = model.library.list(listID)
        HStack(spacing: 10) {
            Ring(done: false)
            TextField("New task", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(add)
                .onExitCommand { model.isAddingTask = false }
            Menu {
                ForEach(model.library.lists) { l in
                    Button(l.name) { listID = l.id }
                }
                Button("No List") { listID = nil }
            } label: {
                chip(list?.name ?? "No list", hex: list?.colorHex ?? "#8e8e93")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Menu {
                ForEach(Planner.lengths, id: \.self) { m in
                    Button(TimeFormat.duration(minutes: m)) { minutes = m }
                }
            } label: {
                chip(TimeFormat.duration(minutes: parsed.minutes ?? minutes), hex: "#5b5fe6")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 12).frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule))
        .padding(.bottom, 4)
        .onAppear {
            if case .list(let id) = model.selection { listID = id } else { listID = listID ?? model.library.lists.first?.id }
            focused = true
        }
    }

    private func chip(_ label: String, hex: String) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.eventInk(hex))
            .padding(.horizontal, 9).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.eventFill(hex)))
    }

    private func add() {
        guard model.addTask(text, listID: listID, minutes: minutes) != nil else {
            model.isAddingTask = false
            return
        }
        text = ""
        focused = true
    }
}

/// Everything about one task, in a popover.
struct TaskEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    @State private var title = ""

    var body: some View {
        if let task = model.library.task(taskID) {
            Form {
                TextField("Title", text: $title)
                    .onSubmit { model.update(taskID) { $0.title = title } }
                Picker("List", selection: binding(\.listID, task)) {
                    Text("No list").tag(UUID?.none)
                    ForEach(model.library.lists) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Length", selection: binding(\.minutes, task)) {
                    let options = Planner.lengths.contains(task.minutes) ? Planner.lengths : (Planner.lengths + [task.minutes]).sorted()
                    ForEach(options, id: \.self) { Text(TimeFormat.duration(minutes: $0)).tag($0) }
                }
                Toggle("Due date", isOn: Binding(
                    get: { task.due != nil },
                    set: { on in model.update(taskID) { $0.due = on ? model.planner.calendar.startOfDay(for: model.now) : nil } }))
                if let due = task.due {
                    DatePicker("Due", selection: Binding(get: { due }, set: { d in model.update(taskID) { $0.due = d } }), displayedComponents: .date)
                }
                Toggle(isOn: binding(\.isFocusBlock, task)) {
                    Text("Focus block")
                    Text("Focus starts by itself when the block begins.")
                }
                if let start = task.start, let end = task.end {
                    LabeledContent("Block") {
                        HStack {
                            Text(model.format.range(start, end))
                            if !task.isDone {
                                Button("Move Back to List") { model.unschedule(taskID) }
                            }
                        }
                    }
                }
                HStack {
                    Button("Delete", role: .destructive) {
                        dismiss()
                        model.delete(taskID)
                    }
                    Spacer()
                    Button("Done") {
                        model.update(taskID) { $0.title = title }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
            .onAppear { title = task.title }
            .onDisappear { if model.library.task(taskID) != nil { model.update(taskID) { $0.title = title } } }
        }
    }

    private func binding<V>(_ key: WritableKeyPath<TaskItem, V>, _ task: TaskItem) -> Binding<V> {
        Binding(get: { task[keyPath: key] }, set: { v in model.update(taskID) { $0[keyPath: key] = v } })
    }
}
