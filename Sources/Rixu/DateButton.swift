import SwiftUI

struct DateButton: View {
    let title: String
    @Binding var selection: Date
    var latest: Date?
    var includesTime = false
    @State private var isPresented = false
    @State private var draft = Date.now
    @State private var month = Date.now

    init(_ title: String, selection: Binding<Date>, latest: Date? = nil, includesTime: Bool = false) {
        self.title = title
        self._selection = selection
        self.latest = latest
        self.includesTime = includesTime
    }

    var body: some View {
        Button {
            draft = selection
            month = WorkCalendar.monthStart(selection)
            isPresented = true
        } label: {
            Text(WorkCalendar.label(selection, includesTime ? "yyyy/MM/dd HH:mm" : "yyyy/MM/dd"))
                .monospacedDigit()
                .padding(.horizontal, 3)
        }
        .buttonStyle(.bordered)
        .help("选择\(title)")
        .accessibilityLabel("选择\(title)")
        .accessibilityValue(WorkCalendar.label(selection, includesTime ? "yyyy年M月d日 HH时mm分" : "yyyy年M月d日"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                MonthNavigation(month: month) { month = WorkCalendar.move(month, by: $0, component: .month) }
                MonthGrid(month: month, selected: draft, latest: latest, select: select)
                if includesTime {
                    Divider().padding(.vertical, 3)
                    HStack(spacing: 8) {
                        DatePicker("时间", selection: $draft, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.field)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .fixedSize()
                        Spacer(minLength: 8)
                        Button("取消") { isPresented = false }.buttonStyle(.borderless)
                        Button("应用", action: apply)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(14)
            .frame(width: 292)
        }
    }

    private func select(_ day: Date) {
        let calendar = WorkCalendar.calendar
        let time = calendar.dateComponents([.hour, .minute], from: draft)
        let result = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                   second: 0, of: day) ?? day
        draft = latest.map { min($0, result) } ?? result
        month = WorkCalendar.monthStart(day)
        if !includesTime { apply() }
    }

    private func apply() {
        selection = draft
        isPresented = false
    }
}
