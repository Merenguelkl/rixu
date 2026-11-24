import SwiftUI

struct MonthGrid: View {
    let month: Date
    let selected: Date
    var latest: Date?
    var showsMarkers = false
    var scheduled: Set<Date> = []
    var completed: Set<Date> = []
    let select: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let calendar = WorkCalendar.calendar
        let days = WorkCalendar.monthGridDays(month)

        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                Text(weekday)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 23)
                    .accessibilityHidden(true)
            }
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let isToday = calendar.isDateInToday(day)
                let outsideMonth = !calendar.isDate(day, equalTo: month, toGranularity: .month)
                let hasSchedule = scheduled.contains(day)
                let hasCompletion = completed.contains(day)
                Button { select(day) } label: {
                    VStack(spacing: 2) {
                        Text(String(calendar.component(.day, from: day)))
                            .font(.callout.weight(isSelected || isToday ? .semibold : .regular))
                            .monospacedDigit()
                        if showsMarkers {
                            HStack(spacing: 3) {
                                if hasSchedule { Circle().strokeBorder(lineWidth: 1).frame(width: 4, height: 4) }
                                if hasCompletion { Circle().frame(width: 4, height: 4) }
                            }
                            .frame(height: 5)
                            .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: showsMarkers ? 33 : 29)
                    .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : outsideMonth ? .secondary : .primary)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isSelected ? Color.primary : Color.primary.opacity(isToday ? 0.10 : 0))
                    }
                    .modifier(RowHighlight(baseOpacity: 0, radius: 7, tint: .primary))
                }
                .buttonStyle(.plain)
                .disabled(latest.map { day > $0 } ?? false)
                .opacity(latest.map { day > $0 ? 0.35 : 1 } ?? 1)
                .accessibilityLabel(WorkCalendar.label(day, "yyyy年M月d日 EEEE"))
                .accessibilityValue([isToday ? "今天" : "", hasSchedule ? "有安排" : "", hasCompletion ? "有完成记录" : ""]
                    .filter { !$0.isEmpty }.joined(separator: "，"))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

struct MonthNavigation: View {
    let month: Date
    var today: (() -> Void)?
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(WorkCalendar.label(month, "yyyy年M月"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let today {
                Button("今天", action: today).buttonStyle(.borderless)
                    .padding(.trailing, 6)
            }
            IconButton(icon: "chevron.left", label: "上个月", size: 27) { move(-1) }
            IconButton(icon: "chevron.right", label: "下个月", size: 27) { move(1) }
        }
    }
}
