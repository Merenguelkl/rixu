import AppKit
import SwiftUI

private enum MenuTab: String, CaseIterable {
    case pending = "待办"
    case done = "已完成"
}

struct MenuContent: View {
    let store: TaskStore
    let applyTransparency: (GlassTransparency) -> Void
    let hoverSettingChanged: (Bool) -> Void

    @AppStorage(GlassTransparency.preferenceKey) private var transparency = GlassTransparency.standard
    @AppStorage(PanelHover.preferenceKey) private var hoverEnabled = false
    @State private var workspace: Workspace?
    @State private var settingsSection = SettingsSection.general
    @State private var calendarDay = Date.now
    @State private var reports = ReportPageState()
    @State private var models = ModelPageState()
    @State private var tab = MenuTab.pending
    @State private var day = Date.now
    @State private var taskDraft = ""
    @State private var doneDraft = ""
    @State private var editTask: WorkItem?
    @State private var wasNewTask = false
    @State private var wasNewDone = false
    @State private var editDone: ManualDone?
    @State private var expanded = Set<UUID>()
    @State private var pendingRemoval: DoneEntry?
    @State private var now = Date.now
    @FocusState private var inputFocused: Bool

    private var draft: Binding<String> {
        tab == .pending ? $taskDraft : $doneDraft
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            Group {
                switch workspace {
                case .calendar:
                    CalendarWorkspace(store: store, selected: $calendarDay)
                case .reports:
                    ReportWorkspace(store: store, openSettings: {
                        settingsSection = .models
                        navigate(to: .settings)
                    }, state: reports)
                case .settings:
                    SettingsWorkspace(section: $settingsSection, hoverEnabled: $hoverEnabled,
                                      transparency: $transparency, models: models)
                case nil:
                    VStack(spacing: 14) { taskContent }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let message = store.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: workspace) {
            if workspace == nil, editTask == nil, editDone == nil { focusInput() }
        }
        .onChange(of: transparency, initial: true) { _, value in applyTransparency(value) }
        .onChange(of: hoverEnabled) { _, value in hoverSettingChanged(value) }
        .onReceive(NotificationCenter.default.publisher(for: .rixuPanelOpened)) { _ in
            now = .now
            workspace = nil
            guard editTask == nil, editDone == nil else { return }
            tab = .pending
            focusInput()
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) {
            if workspace == nil { now = $0 }
        }
    }

    @ViewBuilder private var taskContent: some View {
        if let task = editTask {
            TaskEditor(task: task, store: store) { saved in
                if saved, wasNewTask { taskDraft = "" }
                editTask = nil
                focusInput()
            }
                .id(task.id)
        } else if let entry = editDone {
            ManualEditor(entry: entry, store: store) { saved in
                if saved {
                    if wasNewDone { doneDraft = "" }
                    if let updated = store.manualEntry(entry.id) { day = updated.date }
                }
                editDone = nil
                focusInput()
            }
                .id(entry.id)
        } else {
            Picker("清单", selection: Binding(get: { tab }, set: { newTab in
                guard newTab != tab else { return }
                if newTab == .done { day = .now }
                tab = newTab
            })) {
                ForEach(MenuTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            if tab == .done { dayBar }
            list
            if let removal = pendingRemoval {
                DeleteConfirmation(message: "删除这条完成记录？", cancel: { pendingRemoval = nil }) {
                    store.remove(manual: removal.id)
                    if store.message == nil { pendingRemoval = nil }
                }
            }
            composer
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if workspace != nil {
                IconButton(icon: "chevron.left", label: "返回清单", size: 29) { navigate(to: nil) }
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(workspace?.rawValue ?? "日序")
                    .font(.system(size: workspace == nil ? 25 : 19, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if workspace == nil {
                    Text(WorkCalendar.label(now, "M月d日 EEEE"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    destination(.calendar, icon: "calendar")
                    destination(.reports, icon: "doc.text")
                    destination(.settings, icon: "gear")
                }
            }
        }
        .frame(minHeight: 48)
    }

    private func destination(_ page: Workspace, icon: String) -> some View {
        IconButton(icon: icon, label: "打开" + page.rawValue, size: 32) { navigate(to: page) }
            .background(.primary.opacity(workspace == page ? 0.13 : 0), in: .circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityAddTraits(workspace == page ? [.isSelected] : [])
    }

    private func navigate(to page: Workspace?) {
        guard page != workspace else { return }
        inputFocused = false
        workspace = page
    }

    private var dayBar: some View {
        HStack(spacing: 6) {
            IconButton(icon: "chevron.left", label: "前一天") { day = WorkCalendar.move(day, by: -1) }
            DateButton("完成日期", selection: $day, latest: now)
            IconButton(icon: "chevron.right", label: "后一天") { day = min(WorkCalendar.move(day, by: 1), now) }
                .disabled(WorkCalendar.calendar.isDate(day, inSameDayAs: now))
            Spacer()
            Button("今天") { day = .now }
                .buttonStyle(.borderless)
                .disabled(WorkCalendar.calendar.isDate(day, inSameDayAs: now))
        }
    }

    @ViewBuilder private var list: some View {
        if tab == .pending {
            let tasks = store.pending
            if tasks.isEmpty {
                empty("待办清空了", detail: "在下方记一条新的待办", icon: "checklist")
            } else {
                let groups = Dictionary(grouping: tasks) { $0.overdue(at: now) }
                ScrollView {
                    LazyVStack(spacing: 7) {
                        if let overdue = groups[true] { taskGroup("已逾期", overdue, symbol: "exclamationmark.circle") }
                        if let remaining = groups[false] { taskGroup("未完成", remaining) }
                    }
                    .padding(.horizontal, 2)
                }
                .defaultScrollAnchor(.top)
                .frame(maxHeight: .infinity)
            }
        } else {
            let records = store.done(on: day)
            if records.isEmpty {
                empty("当天还没有完成记录", detail: "完成待办后会自动记录，也可以在下方补录", icon: "checkmark.circle")
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        SectionName(title: "完成记录", count: records.count)
                        ForEach(records) { entry in doneRow(entry) }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func empty(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 29, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func taskGroup(_ title: String, _ tasks: [WorkItem], symbol: String? = nil) -> some View {
        Section {
            ForEach(tasks) { task in taskRow(task) }
        } header: {
            SectionName(title: title, count: tasks.count, symbol: symbol)
        }
    }

    private func taskRow(_ task: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 4) {
                IconButton(icon: "circle", label: "完成「\(task.title)」", size: 29) { store.complete(task) }
                    .foregroundStyle(.secondary)
                    .disabled(!task.canComplete)
                Button { wasNewTask = false; editTask = task } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title).font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if let start = task.start, let end = task.end {
                            Text("\(WorkCalendar.label(start, "M/d HH:mm")) – \(WorkCalendar.label(end, "M/d HH:mm"))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(task.overdue(at: now) ? Color.orange : Color.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("编辑任务")
                .accessibilityHint("编辑任务")
                if !task.subtasks.isEmpty {
                    Button { toggleExpansion(task.id) } label: {
                        HStack(spacing: 4) {
                            Text("\(task.completedCount)/\(task.subtasks.count)").monospacedDigit()
                            Image(systemName: expanded.contains(task.id) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.caption.weight(.medium))
                        .frame(minHeight: 29)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(expanded.contains(task.id) ? "收起" : "展开")子项，已完成 \(task.completedCount) 项，共 \(task.subtasks.count) 项")
                }
            }
            if expanded.contains(task.id) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.subtasks) { subtask in
                        HStack(spacing: 6) {
                            IconButton(icon: subtask.completedAt == nil ? "circle" : "checkmark.circle.fill",
                                       label: "\(subtask.completedAt == nil ? "完成" : "取消完成")「\(subtask.title)」", size: 25) {
                                store.toggle(subtask, in: task)
                            }
                            .foregroundStyle(subtask.completedAt == nil ? Color.secondary : Color.accentColor)
                            Text(subtask.title)
                                .font(.callout)
                                .strikethrough(subtask.completedAt != nil)
                                .foregroundStyle(subtask.completedAt == nil ? .primary : .secondary)
                            Spacer(minLength: 4)
                            if subtask.separate {
                                Image(systemName: "checkmark.rectangle")
                                    .help("单独记入已完成")
                                    .accessibilityLabel("单独记入已完成")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        .modifier(RowHighlight(baseOpacity: 0, radius: 6))
                    }
                    if task.canComplete {
                        Button("完成任务") { store.complete(task) }.buttonStyle(.borderless)
                            .padding(.leading, 6)
                    }
                }
                .padding(.leading, 30)
                .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
        .modifier(RowHighlight())
    }

    private func doneRow(_ entry: DoneEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 23)
                    .accessibilityHidden(true)
                DoneLabel(entry: entry)
                if !entry.details.isEmpty {
                    IconButton(icon: expanded.contains(entry.id) ? "chevron.down" : "chevron.right",
                               label: expanded.contains(entry.id) ? "收起子项" : "展开子项") {
                        toggleExpansion(entry.id)
                    }
                }
                Menu {
                    if entry.source == .manual {
                        Button("编辑") { wasNewDone = false; editDone = store.manualEntry(entry.id) }
                        Button("删除", role: .destructive) { pendingRemoval = entry }
                    } else {
                        Button("撤销完成") { store.restore(entry) }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 27, height: 27)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("「\(entry.title)」的操作")
            }
            if expanded.contains(entry.id) {
                ForEach(Array(entry.details.enumerated()), id: \.offset) { _, title in
                    Label(title, systemImage: "checkmark")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.leading, 32)
                }
            }
        }
        .padding(7)
        .modifier(RowHighlight())
    }

    private var composer: some View {
        HStack(spacing: 6) {
            let done = tab == .done
            let label = done ? "补录完成事项" : "添加待办"
            IconButton(icon: "plus", label: done ? "设置补录日期" : "添加带时间或子项的待办", size: 32) {
                if done {
                    wasNewDone = true
                    editDone = ManualDone(title: draft.wrappedValue, date: WorkCalendar.onDay(day))
                } else {
                    wasNewTask = true
                    editTask = WorkItem(title: draft.wrappedValue)
                }
            }
            TextField(label, text: draft)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(quickAdd)
                .accessibilityLabel(label)
            IconButton(icon: "return", label: "保存", size: 32, action: quickAdd)
                .disabled(draft.wrappedValue.trimmed.isEmpty)
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func quickAdd() {
        let title = draft.wrappedValue.trimmed
        guard !title.isEmpty else { return }
        let saved = tab == .pending ? store.save(WorkItem(title: title)) :
            store.save(ManualDone(title: title, date: WorkCalendar.onDay(day)))
        if saved { draft.wrappedValue = "" }
        focusInput()
    }

    private func toggleExpansion(_ id: UUID) {
        if !expanded.insert(id).inserted { expanded.remove(id) }
    }

    private func focusInput() {
        Task { @MainActor in
            await Task.yield()
            inputFocused = true
        }
    }
}

