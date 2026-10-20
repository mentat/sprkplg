import SparkPlugCore
import SwiftUI

/// This week, a column per day: what is due, all-day events, and each day's timeline.
struct WeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = model.planner.week(containing: model.now, weekends: model.library.settings.showWeekends)
        let perDay = days.map { model.items(on: $0) }
        let range = model.layout.hourRange(for: perDay.flatMap(\.timed), days: days, minimum: model.minimumHours)
        let height = CGFloat(range.count) * model.layout.hourHeight

        GeometryReader { geo in
            let columnWidth = max((geo.size.width - 8 - 20 - DayTimeline.labelWidth) / CGFloat(days.count), 40)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: DayTimeline.labelWidth, height: 1)
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        DayHeader(day: day, allDay: perDay[i].allDay).frame(width: columnWidth)
                    }
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }

                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            ForEach(Array(range.hours), id: \.self) { h in
                                Text(model.format.hourLabel(h))
                                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                                    .padding(.trailing, 10)
                                    .frame(height: 14)
                                    .offset(y: CGFloat(h - range.start) * model.layout.hourHeight - 7)
                            }
                        }
                        .frame(width: DayTimeline.labelWidth, height: height, alignment: .topTrailing)
                        ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                            DayColumn(
                                day: day, items: perDay[i].timed, range: range, columnWidth: columnWidth, dayIndex: i,
                                dayCount: days.count
                            )
                            .frame(width: columnWidth, height: height)
                            .zIndex(perDay[i].timed.contains { $0.taskID != nil && $0.taskID == model.movingTaskID } ? 1 : 0)
                        }
                    }
                    .padding(.top, 12).padding(.bottom, 20)
                }
            }
            .padding(.leading, 8).padding(.trailing, 20)
            .coordinateSpace(name: "week")
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }
}

private struct DayHeader: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let allDay: [TimelineItem]

    var body: some View {
        let isToday = model.planner.calendar.isDate(day, inSameDayAs: model.now)
        let due = model.planner.due(on: day, model.library.tasks)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(model.format.weekday(day))
                    .font(.system(size: 11, weight: .semibold)).tracking(0.44)
                    .foregroundStyle(isToday ? Theme.accent : Theme.tertiary)
                Text("\(model.planner.calendar.component(.day, from: day))")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 26, minHeight: 26)
                    .background(Capsule().fill(isToday ? Theme.accent : .clear))
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(allDay) { EventChip(item: $0) }
                ForEach(due) { t in
                    HStack(spacing: 6) {
                        Circle().strokeBorder(Color(hex: model.listColorHex(t.listID)), lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                        Text(t.title).lineLimit(1)
                    }
                    .font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.8))
                    .padding(.horizontal, 7).frame(height: 22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hover))
                    .help("Due: \(t.title)")
                }
            }
            .frame(minHeight: 22, alignment: .top)
        }
        .padding(.horizontal, 6).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hover).frame(width: 1) }
    }
}

private struct DayColumn: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let items: [TimelineItem]
    let range: HourRange
    let columnWidth: CGFloat
    let dayIndex: Int
    let dayCount: Int
    @State private var ghost: Ghost?

    var body: some View {
        let isToday = model.planner.calendar.isDate(day, inSameDayAs: model.now)
        let placed = model.layout.place(items, day: day, range: range)
        ZStack(alignment: .topLeading) {
            HourGrid(range: range, labels: false)
            ForEach(placed) { p in
                let w = (columnWidth - 6) / CGFloat(p.columns)
                BlockView(
                    placed: p, day: day, range: range, compact: true, columnWidth: columnWidth, dayIndex: dayIndex,
                    dayCount: dayCount)
                    .frame(width: max(w - 1, 8))
                    .offset(x: 3 + CGFloat(p.column) * w, y: p.top)
            }
            if let ghost {
                GhostSlot()
                    .frame(width: columnWidth - 6, height: CGFloat(ghost.minutes) - 3)
                    .offset(x: 3, y: model.layout.y(of: ghost.start, day: day, range: range) + 1)
            }
            if isToday {
                NowLine(y: model.layout.y(of: model.now, day: day, range: range), inset: -5)
                    .opacity(model.now >= model.layout.origin(of: day, range: range) ? 1 : 0)
            }
        }
        .frame(width: columnWidth, height: CGFloat(range.count) * model.layout.hourHeight, alignment: .topLeading)
        .background(isToday ? Theme.todayColumn : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hover).frame(width: 1) }
        .contentShape(Rectangle())
        .onDrop(of: [.sparkplugTask], delegate: TimelineDrop(model: model, day: day, range: range, ghost: $ghost))
    }
}
