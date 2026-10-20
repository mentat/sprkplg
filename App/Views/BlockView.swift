import SparkPlugCore
import SwiftUI

/// One item on a timeline. Calendar events are read-only; a task's block can be dragged to a new
/// time (or, on the day, back onto the task list), stretched from its bottom edge, and edited.
struct BlockView: View {
    @Environment(AppModel.self) private var model
    let placed: PlacedItem
    let day: Date
    let range: HourRange
    /// The week's smaller blocks.
    let compact: Bool
    /// The width of one day column (the week), for dragging a block to another day.
    var columnWidth: CGFloat = 0
    /// Which of the week's `dayCount` visible days this is; a block can be dragged only onto those.
    var dayIndex = 0
    var dayCount = 1

    @State private var drag: CGSize = .zero
    @State private var stretch: CGFloat = 0
    @State private var editing = false
    @State private var resizeCursor = false

    private var item: TimelineItem { placed.item }
    private var hour: CGFloat { model.layout.hourHeight }
    /// A quarter hour, in points.
    private var quarter: CGFloat { hour / 4 }

    var body: some View {
        let look = Look(item: item, calendarHex: calendarHex)
        let snappedY = (drag.height / quarter).rounded() * quarter
        let dayShift = compact ? CGFloat(dayOffset(drag.width)) * columnWidth : drag.width
        content(look: look)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: compact ? 6 : 8).fill(look.fill))
            .overlay(border(look))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8))
            .frame(height: max(placed.height + (stretch / quarter).rounded() * quarter, 12))
            .shadow(color: look.shadow, radius: item.isActiveFocus ? 10 : 7, y: item.isActiveFocus ? 6 : 4)
            .background {
                if item.isActiveFocus && !compact {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.focus.opacity(0.45)).padding(-3)
                }
            }
            .overlay(alignment: .bottom) { if item.taskID != nil && !item.isDone { stretchHandle } }
            .offset(x: dayShift, y: snappedY)
            .zIndex(drag == .zero && stretch == 0 ? 0 : 10)
            .opacity(drag == .zero ? 1 : 0.9)
            .help("\(item.title)\n\(model.format.range(item.start, item.end))")
            .gesture(moveGesture)
            .onTapGesture(count: 2) { if item.taskID != nil { editing = true } }
            .popover(isPresented: $editing, arrowEdge: .trailing) {
                if let id = item.taskID { TaskEditor(taskID: id) }
            }
            .contextMenu {
                if let id = item.taskID, let task = model.library.task(id) {
                    TaskMenu(task: task, edit: { editing = true })
                }
            }
    }

    /// Days a horizontal drag moves a week block, kept on the visible days.
    private func dayOffset(_ dx: CGFloat) -> Int {
        guard compact, columnWidth > 0 else { return 0 }
        return min(max(Int((dx / columnWidth).rounded()), -dayIndex), dayCount - 1 - dayIndex)
    }

    private var calendarHex: String {
        if case .event(let c) = item.kind { return model.calendarHex(c) }
        return "#5b5fe6"
    }

    private var lengthMinutes: Double { item.end.timeIntervalSince(item.start) / 60 }
    private var tall: Bool { lengthMinutes > 30 }

    private var padding: EdgeInsets {
        if compact { return EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7) }
        return tall ? EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11) : EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 11)
    }

    @ViewBuilder
    private func content(look: Look) -> some View {
        let time = model.format.range(item.start, item.end)
        if compact {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).strikethrough(item.isDone)
                if lengthMinutes >= 60 {
                    Text(time).font(.system(size: 10.5)).opacity(0.75).lineLimit(1)
                }
            }
            .foregroundStyle(look.ink)
        } else if tall {
            VStack(alignment: .leading, spacing: 2) {
                title(look: look)
                Text(time).font(.system(size: 11.5)).monospacedDigit().opacity(0.75).lineLimit(1)
                if item.isActiveFocus {
                    Spacer(minLength: 0)
                    FocusProgress()
                }
            }
            .foregroundStyle(look.ink)
        } else {
            HStack(spacing: 8) {
                title(look: look)
                Text(time).font(.system(size: 11.5)).monospacedDigit().opacity(0.75).lineLimit(1).layoutPriority(-1)
            }
            .frame(maxHeight: .infinity)
            .foregroundStyle(look.ink)
        }
    }

    private func title(look: Look) -> some View {
        HStack(spacing: 7) {
            if let id = item.taskID {
                if item.isFocus {
                    Bolt().fill(look.ink).frame(width: 13, height: 13)
                } else {
                    Button {
                        model.setDone(id, !item.isDone)
                    } label: {
                        Circle().strokeBorder(look.ink, lineWidth: 1.5)
                            .background(Circle().fill(item.isDone ? look.ink : .clear))
                            .frame(width: 13, height: 13)
                    }
                    .buttonStyle(.plain)
                    .help(item.isDone ? "Mark as not done" : "Mark as done")
                }
            }
            Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                .strikethrough(item.isDone)
        }
    }

    @ViewBuilder
    private func border(_ look: Look) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 6 : 8)
        switch look.edge {
        case .none: EmptyView()
        case .solid(let c): shape.strokeBorder(c, lineWidth: 1)
        case .dashed(let c): shape.strokeBorder(c, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// The bottom edge of a task's block: drag to change its length.
    private var stretchHandle: some View {
        Color.clear
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { setResizeCursor($0) }
            .onDisappear { setResizeCursor(false) }
            .gesture(
                // Measured in the timeline's space: the handle itself moves as the block grows.
                DragGesture(minimumDistance: 1, coordinateSpace: .named(compact ? "week" : "day"))
                    .onChanged { stretch = $0.translation.height }
                    .onEnded { v in
                        let quarters = Int((v.translation.height / quarter).rounded())
                        if let id = item.taskID, let task = model.library.task(id) {
                            model.resize(id, minutes: task.minutes + quarters * 15)
                        }
                        stretch = 0
                    })
    }

    /// Pushes or pops the resize cursor, never more than once each way.
    private func setResizeCursor(_ on: Bool) {
        guard on != resizeCursor else { return }
        resizeCursor = on
        if on { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(compact ? "week" : "day"))
            .onChanged { v in
                guard let id = item.taskID, !item.isDone else { return }
                drag = v.translation
                if model.movingTaskID != id { model.movingTaskID = id }
            }
            .onEnded { v in
                defer {
                    drag = .zero
                    model.movingTaskID = nil
                }
                guard let id = item.taskID, !item.isDone else { return }
                if !compact && v.location.x < DayView.taskColumnWidth {
                    model.unschedule(id)
                    return
                }
                let quarters = Int((v.translation.height / quarter).rounded())
                let days = dayOffset(v.translation.width)
                guard quarters != 0 || days != 0 else { return }
                let shifted = model.planner.calendar.date(byAdding: .day, value: days, to: item.start) ?? item.start
                model.schedule(id, at: shifted.addingTimeInterval(TimeInterval(quarters * 15 * 60)))
            }
    }
}

/// How an item is drawn: events in their calendar's colour, tasks dashed indigo, focus yellow.
private struct Look {
    enum Edge {
        case none
        case solid(Color)
        case dashed(Color)
    }

    var fill: Color
    var ink: Color
    var edge: Edge
    var shadow: Color

    init(item: TimelineItem, calendarHex: String) {
        switch item.kind {
        case .event:
            fill = Theme.eventFill(calendarHex)
            ink = Theme.eventInk(calendarHex)
            edge = .none
            shadow = .clear
        case .task where item.isFocus:
            fill = Theme.focus
            ink = Theme.focusInk
            edge = .solid(Theme.focusEdge)
            shadow = Color(red: 0.63, green: 0.47, blue: 0).opacity(item.isActiveFocus ? 0.3 : 0.25)
        case .task:
            fill = Theme.taskFill
            ink = Theme.taskInk
            edge = .dashed(Theme.taskEdge)
            shadow = .clear
        }
        if item.isDone && item.taskID != nil { fill = fill.opacity(0.6) }
    }
}

/// The running focus block's progress bar and countdown.
struct FocusProgress: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let active = model.activeFocus(at: model.clock()) {
                HStack(spacing: 10) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.focusInk.opacity(0.15))
                            Capsule().fill(Theme.focusInk).frame(width: g.size.width * active.progress)
                        }
                    }
                    .frame(height: 5)
                    Text("\(TimeFormat.countdown(seconds: active.secondsLeft)) left")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }
        }
    }
}
