import SparkPlugCore
import SwiftUI

/// The window: sidebar, toolbar, and the day or week.
struct RootView: View {
    @Environment(AppModel.self) private var model

    enum Mode: Hashable { case day, week }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 320)
        } detail: {
            Group {
                if model.selection == .week { WeekView() } else { DayView() }
            }
            .navigationTitle(model.title)
            .navigationSubtitle(model.subtitle)
            .toolbar { toolbar }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        .alert(
            "SparkPlug", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            presenting: model.notice
        ) { _ in
            Button("OK") { model.notice = nil }
        } message: { Text($0) }
    }

    private var mode: Binding<Mode> {
        Binding(
            get: { model.selection == .week ? .week : .day },
            set: { m in
                if m == .week {
                    model.selection = .week
                } else if model.selection == .week {
                    model.selection = .today
                }
            })
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: mode) {
                Text("Day").tag(Mode.day)
                Text("Week").tag(Mode.week)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .help("Day (⌘1) or Week (⌘2)")
        }
        ToolbarItem(placement: .primaryAction) {
            FocusButton()
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.beginNewTask()
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .help("New task (⌘N)")
        }
    }
}

/// The toolbar's Focus button: yellow with the countdown while focusing, plain otherwise.
struct FocusButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let active = model.activeFocus(at: model.clock())
            Button {
                model.toggleFocus()
            } label: {
                if let active {
                    HStack(spacing: 7) {
                        Bolt().fill(Theme.focusInk).frame(width: 14, height: 14)
                        Text(TimeFormat.countdown(seconds: active.secondsLeft))
                            .monospacedDigit().fontWeight(.semibold)
                        Text(active.task.title).fontWeight(.medium).opacity(0.75).lineLimit(1)
                            .frame(maxWidth: 180, alignment: .leading)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.focusInk)
                    .padding(.leading, 10).padding(.trailing, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Theme.focus))
                    .shadow(color: Color(red: 0.47, green: 0.35, blue: 0).opacity(0.25), radius: 1.5, y: 1)
                } else {
                    HStack(spacing: 6) {
                        Bolt().stroke(style: StrokeStyle(lineWidth: 1.5, lineJoin: .round)).frame(width: 14, height: 14)
                        Text("Focus").font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                }
            }
            .buttonStyle(.plain)
            .disabled(active == nil && !model.canFocus)
            .help(
                active != nil
                    ? "Stop focusing (⇧⌘F)"
                    : "Focus on the block happening now, or start the first unscheduled task now (⇧⌘F)")
        }
    }
}
