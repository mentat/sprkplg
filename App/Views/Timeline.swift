import SparkPlugCore
import SwiftUI
import UniformTypeIdentifiers

/// The day: the task list on the left, today's timeline on the right.
struct DayView: View {
    static let taskColumnWidth: CGFloat = 372

    var body: some View {
        HStack(spacing: 0) {
            TaskColumn().frame(width: Self.taskColumnWidth)
            Rectangle().fill(Theme.rule).frame(width: 1)
            DayTimeline()
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        .coordinateSpace(name: "day")
    }
}

extension UTType {
    /// A task dragged from SparkPlug's own list (declared in Info.plist).
    static let sparkplugTask = UTType(exportedAs: "io.sprkplg.task")
}

/// Where a dragged task would land, shown as a dashed slot.
struct Ghost: Equatable {
    var start: Date
    var minutes: Int
}

/// Today's hours, its events and blocks, the now line, and the drop target for tasks.
struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    @State private var ghost: Ghost?

    static let labelWidth: CGFloat = 56

    var body: some View {
        let day = model.now
        let (timed, allDay) = model.items(on: day)
        let range = model.layout.hourRange(for: timed, days: [day], minimum: model.minimumHours)
        let placed = model.layout.place(timed, day: day, range: range)
        let height = CGFloat(range.count) * model.layout.hourHeight

        VStack(spacing: 0) {
            if model.access != .granted { AccessBanner() }
            if !allDay.isEmpty { AllDayRow(items: allDay) }
            ScrollViewReader { proxy in
                ScrollView {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            HourGrid(range: range, labels: true)
                            ForEach(placed) { p in
                                let w = (geo.size.width - 8) / CGFloat(p.columns)
                                BlockView(placed: p, day: day, range: range, compact: false)
                                    .frame(width: max(w - 2, 10))
                                    .offset(x: 4 + CGFloat(p.column) * w, y: p.top)
                            }
                            if let ghost {
                                GhostSlot()
                                    .frame(width: geo.size.width - 8, height: CGFloat(ghost.minutes) - 3)
                                    .offset(x: 4, y: model.layout.y(of: ghost.start, day: day, range: range) + 1)
                            }
                            NowLine(y: model.layout.y(of: model.now, day: day, range: range), inset: -8)
                                .opacity(model.now >= model.layout.origin(of: day, range: range) ? 1 : 0)
                        }
                        .frame(width: geo.size.width, height: height, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [.sparkplugTask],
                            delegate: TimelineDrop(model: model, day: day, range: range, ghost: $ghost))
                    }
                    .frame(height: height)
                    .padding(.leading, 12 + Self.labelWidth).padding(.trailing, 24)
                    .padding(.top, 24).padding(.bottom, 34)
                    .background(alignment: .topLeading) { scrollAnchors(range: range) }
                }
                .onAppear { scrollToNow(proxy, range: range) }
            }
        }
    }

    /// Invisible markers, one per hour, so the timeline can open scrolled to the current time.
    private func scrollAnchors(range: HourRange) -> some View {
        VStack(spacing: 0) {
            ForEach(range.start..<range.end, id: \.self) { h in
                Color.clear.frame(height: model.layout.hourHeight).id(h)
            }
        }
        .padding(.top, 24)
    }

    private func scrollToNow(_ proxy: ScrollViewProxy, range: HourRange) {
        let hour = model.planner.calendar.component(.hour, from: model.now)
        let target = min(max(hour - 1, range.start), max(range.end - 1, range.start))
        proxy.scrollTo(target, anchor: .top)
    }
}

/// Drops from the task list: a dashed slot follows the pointer (snapped to 15 minutes) and the
/// task gets its block where it is let go.
struct TimelineDrop: DropDelegate {
    let model: AppModel
    let day: Date
    let range: HourRange
    @Binding var ghost: Ghost?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.sparkplugTask]) && model.draggingTaskID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let id = model.draggingTaskID, let task = model.library.task(id) else { return nil }
        let start = model.layout.time(atY: info.location.y, day: day, range: range)
        let g = Ghost(start: start, minutes: task.minutes)
        if g != ghost { ghost = g }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { ghost = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            ghost = nil
            model.draggingTaskID = nil
        }
        guard info.hasItemsConforming(to: [.sparkplugTask]), let id = model.draggingTaskID else { return false }
        return model.schedule(id, at: model.layout.time(atY: info.location.y, day: day, range: range))
    }
}

/// Hour rules, with labels to their left on the day's timeline.
struct HourGrid: View {
    @Environment(AppModel.self) private var model
    let range: HourRange
    let labels: Bool

    var body: some View {
        ForEach(Array(range.hours), id: \.self) { h in
            let y = CGFloat(h - range.start) * model.layout.hourHeight
            Rectangle().fill(Theme.hourLine).frame(height: 1)
                .offset(y: y)
            if labels {
                Text(model.format.hourLabel(h))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    .frame(width: 46, alignment: .trailing)
                    .offset(x: -DayTimeline.labelWidth, y: y - 8)
            }
        }
    }
}

struct NowLine: View {
    let y: CGFloat
    let inset: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Theme.now).frame(height: 1.5)
            Circle().fill(Theme.now).frame(width: 9, height: 9).offset(x: -1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, inset)
        .offset(y: y - 0.75)
        .allowsHitTesting(false)
        .zIndex(3)
    }
}

struct GhostSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.06)))
            .allowsHitTesting(false)
    }
}

/// All-day events, as chips above the timeline.
struct AllDayRow: View {
    @Environment(AppModel.self) private var model
    let items: [TimelineItem]

    var body: some View {
        HStack(spacing: 6) {
            Text("all-day").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                .frame(width: DayTimeline.labelWidth - 10, alignment: .trailing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { EventChip(item: $0) }
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 24).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }
}

struct EventChip: View {
    @Environment(AppModel.self) private var model
    let item: TimelineItem

    var body: some View {
        let hex: String = {
            if case .event(let c) = item.kind { return model.calendarHex(c) }
            return "#5b5fe6"
        }()
        Text(item.title)
            .font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            .foregroundStyle(Theme.eventInk(hex))
            .padding(.horizontal, 7).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.eventFill(hex)))
            .help(item.title)
    }
}

/// Asks for calendar access, or explains where to turn it on.
struct AccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(Theme.accent)
            Text(
                model.access == .notDetermined
                    ? "Show your meetings next to your tasks. SparkPlug reads the calendars on this Mac and sends nothing anywhere."
                    : "SparkPlug can't see your calendars. Turn on access in System Settings › Privacy & Security › Calendars."
            )
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .lineLimit(2)
            Spacer(minLength: 8)
            if model.access == .notDetermined {
                Button("Allow Access") { Task { await model.requestCalendarAccess() } }
            } else {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.chipFill.opacity(0.6))
    }
}
