import SwiftUI

struct TaskEditor: View {
    @State var task: WorkItem
    let store: TaskStore
    let onClose: (Bool) -> Void
    @FocusState private var focus: UUID?
    @State private var deleteConfirmed = false

    private var exists: Bool { store.tasks.contains { $0.id == task.id } }
    private var invalidRange: Bool {
        guard let start = task.start, let end = task.end else { return false }
        return end < start
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exists ? "编辑待办" : "新建待办").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(icon: "xmark", label: "取消") { onClose(false) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("任务名称").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            TextField("任务名称", text: $task.title, prompt: Text("要做什么？"))
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: task.id)
                                .onSubmit(save)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("设置时间范围", isOn: Binding(
                                get: { task.start != nil },
                                set: { enabled in
                                    task.start = enabled ? .now : nil
                                    task.end = task.start?.addingTimeInterval(3600)
                                }
                            ))
                            if let start = task.start, let end = task.end {
                                HStack(spacing: 12) {
                                    timeField("开始", selection: Binding(get: { task.start ?? start }, set: { task.start = $0 }))
                                    timeField("结束", selection: Binding(get: { task.end ?? end }, set: { task.end = $0 }))
                                }
                                if invalidRange {
                                    Label("结束时间不能早于开始时间", systemImage: "exclamationmark.circle")
                                        .font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                        Divider()
                        HStack {
                            Text("子项").font(.headline)
                            Spacer()
                            Button("添加子项", systemImage: "plus") {
                                let subtask = Subtask()
                                task.subtasks.append(subtask)
                                focus = subtask.id
                            }
                            .buttonStyle(.borderless)
                        }
                        ForEach($task.subtasks) { $subtask in
                            let id = subtask.id
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    TextField("子项名称", text: $subtask.title)
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focus, equals: id)
                                    Menu {
                                        if let index = task.subtasks.firstIndex(where: { $0.id == id }) {
                                            Button("上移", systemImage: "arrow.up") {
                                                task.subtasks.swapAt(index, index - 1)
                                            }.disabled(index == 0)
                                            Button("下移", systemImage: "arrow.down") {
                                                task.subtasks.swapAt(index, index + 1)
                                            }.disabled(index == task.subtasks.count - 1)
                                        }
                                        Divider()
                                        Button("删除子项", systemImage: "trash", role: .destructive) {
                                            task.subtasks.removeAll { $0.id == id }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                    .accessibilityLabel("子项排序与删除")
                                }
                                Toggle("单独记入 Done", isOn: $subtask.separate)
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(.primary.opacity(0.045), in: .rect(cornerRadius: 8))
                            .id(id)
                        }
                    }
                    .padding(3)
                }
                .onChange(of: focus) {
                    if let focus, focus != task.id { proxy.scrollTo(focus, anchor: .center) }
                }
            }
            if deleteConfirmed {
                DeleteConfirmation(
                    message: "删除待办及其子项的完成记录？",
                    cancel: { deleteConfirmed = false }
                ) {
                    store.remove(task: task.id)
                    if store.message == nil { onClose(false) }
                }
            } else {
                HStack {
                    if exists {
                        IconButton(icon: "trash", label: "删除待办") { deleteConfirmed = true }
                    }
                    Spacer()
                    Button("取消") { onClose(false) }
                    Button("保存", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(task.title.trimmed.isEmpty || invalidRange)
                }
            }
        }
        .task { focus = task.id }
    }

    private func timeField(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            DateButton(title + "时间", selection: selection, includesTime: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard !task.title.trimmed.isEmpty, !invalidRange else { return }
        task.title = task.title.trimmed
        task.subtasks = task.subtasks.compactMap { item in
            let title = item.title.trimmed
            guard !title.isEmpty else { return nil }
            var cleaned = item
            cleaned.title = title
            return cleaned
        }
        if store.save(task) { onClose(true) }
    }
}

struct ManualEditor: View {
    @State var entry: ManualDone
    let store: TaskStore
    let onClose: (Bool) -> Void
    @FocusState private var focus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("完成记录").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(icon: "xmark", label: "取消") { onClose(false) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("完成事项").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("完成事项", text: $entry.title, prompt: Text("完成了什么？"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focus)
                    .onSubmit(save)
            }
            HStack {
                Text("完成日期")
                DateButton("完成日期", selection: $entry.date, latest: max(.now, entry.date))
            }
            Spacer()
            HStack {
                Spacer()
                Button("取消") { onClose(false) }
                Button("保存", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(entry.title.trimmed.isEmpty)
            }
        }
        .task { focus = true }
    }

    private func save() {
        guard !entry.title.trimmed.isEmpty else { return }
        entry.title = entry.title.trimmed
        entry.date = WorkCalendar.onDay(entry.date)
        if store.save(entry) { onClose(true) }
    }
}
