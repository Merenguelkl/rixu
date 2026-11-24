import SwiftUI

struct CalendarWorkspace: View {
    let store: TaskStore
    @Binding var selected: Date

    private var month: Date { WorkCalendar.monthStart(selected) }

    var body: some View {
        let calendar = WorkCalendar.calendar
        let gridDays = WorkCalendar.monthGridDays(month)
        let interval = DateInterval(start: gridDays[0], end: WorkCalendar.move(gridDays[41], by: 1))
        let scheduled = store.pending.filter { $0.scheduled(in: interval) }
        let scheduledDays = Set(gridDays.filter { date in
            guard let day = calendar.dateInterval(of: .day, for: date) else { return false }
            return scheduled.contains { $0.scheduled(in: day) }
        })
        let recordedDays = Set(store.done(in: interval).map { calendar.startOfDay(for: $0.date) })

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                MonthNavigation(month: month, today: { navigate(to: .now) }) { step in
                    navigate(to: WorkCalendar.move(month, by: step, component: .month))
                }
                MonthGrid(month: month, selected: selected, showsMarkers: true,
                          scheduled: scheduledDays, completed: recordedDays, select: navigate)
                HStack(spacing: 12) {
                    Label("有安排", systemImage: "circle")
                    Label("有完成记录", systemImage: "circle.fill")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Divider().padding(.vertical, 2)
                agenda
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
    }

    private var agenda: some View {
        let due = WorkCalendar.calendar.dateInterval(of: .day, for: selected).map { day in
            store.pending.filter { $0.scheduled(in: day) }.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        } ?? []
        let records = store.done(on: selected)
        return Group {
            Text(WorkCalendar.label(selected, "M月d日 EEEE"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            SectionName(title: "待办安排", count: due.count, symbol: "circle")
            if due.isEmpty { Text("没有安排").font(.callout).foregroundStyle(.secondary) }
            ForEach(due) { task in
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.body.weight(.medium))
                    if let start = task.start, let end = task.end {
                        Text("\(WorkCalendar.label(start, "M/d HH:mm")) – \(WorkCalendar.label(end, "M/d HH:mm"))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .modifier(RowHighlight())
            }
            SectionName(title: "已完成", count: records.count, symbol: "checkmark.circle")
                .padding(.top, 4)
            if records.isEmpty { Text("没有完成记录").font(.callout).foregroundStyle(.secondary) }
            ForEach(records) { entry in
                Group {
                    if entry.details.isEmpty {
                        DoneLabel(entry: entry)
                    } else {
                        DisclosureGroup {
                            ForEach(Array(entry.details.enumerated()), id: \.offset) { _, detail in
                                Text(detail).font(.callout).foregroundStyle(.secondary)
                            }
                        } label: { DoneLabel(entry: entry) }
                    }
                }
                .padding(6)
                .modifier(RowHighlight())
            }
        }
    }

    private func navigate(to day: Date) {
        selected = day
    }
}
