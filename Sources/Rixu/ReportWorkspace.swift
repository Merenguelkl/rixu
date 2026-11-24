import AppKit
import SwiftUI

enum ReportKind: String, CaseIterable {
    case day = "日报"
    case week = "周报"
    case month = "月报"

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

@MainActor @Observable
final class ReportPageState {
    struct Period: Hashable {
        let kind: ReportKind
        let start: Date
    }

    var kind = ReportKind.week
    var date = Date.now
    var drafts: [Period: String] = [:]
    @ObservationIgnored var request: Task<Void, Never>?
    var generating = false
    var status: String?
    var failed = false
    var confirmReplace = false
}

struct ReportWorkspace: View {
    let store: TaskStore
    let openSettings: () -> Void
    @Bindable var state: ReportPageState

    @AppStorage(ModelSettings.addressKey) private var address = ModelEndpoint.defaultAddress
    @AppStorage(ModelSettings.modelKey) private var model = ModelSettings.defaultModel

    private var interval: DateInterval {
        WorkCalendar.calendar.dateInterval(of: state.kind.component, for: state.date) ?? DateInterval(start: state.date, end: state.date)
    }

    private var rangeLabel: String {
        let firstDay = WorkCalendar.label(interval.start, "yyyy年M月d日")
        if state.kind == .day { return firstDay }
        let last = WorkCalendar.move(interval.end, by: -1)
        let calendar = WorkCalendar.calendar
        let format = calendar.isDate(last, equalTo: interval.start, toGranularity: .year) ? "M月d日" : "yyyy年M月d日"
        return firstDay + " – " + WorkCalendar.label(last, format)
    }

    private var period: ReportPageState.Period { .init(kind: state.kind, start: interval.start) }

    var body: some View {
        let period = period
        let currentDraft = state.drafts[period, default: ""]
        let count = store.doneCount(in: interval)
        VStack(alignment: .leading, spacing: 12) {
            Picker("报告类型", selection: $state.kind) {
                ForEach(ReportKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(state.generating)

            HStack(spacing: 4) {
                IconButton(icon: "chevron.left", label: "上一个周期") { move(-1) }
                DateButton("报告日期", selection: $state.date)
                IconButton(icon: "chevron.right", label: "下一个周期") { move(1) }
                Spacer()
                Button("本期") { state.date = .now }.buttonStyle(.borderless)
            }
            .disabled(state.generating)
            VStack(alignment: .leading, spacing: 5) {
                Text(rangeLabel).font(.headline)
                Text(count == 0 ? "此时段没有完成记录" : "\(count) 条完成记录 · \(model)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { state.drafts[period, default: ""] }, set: { state.drafts[period] = $0 }))
                    .font(.body)
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .accessibilityLabel("报告草稿")
                    .disabled(state.generating)
                if currentDraft.isEmpty {
                    Text("报告草稿会显示在这里，也可以直接编辑")
                        .foregroundStyle(.secondary)
                        .padding(.top, 13)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary) }
            if state.confirmReplace {
                HStack(spacing: 8) {
                    Text("重新生成会取代当前草稿。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { state.confirmReplace = false }
                    Button("重新生成") {
                        state.confirmReplace = false
                        generate()
                    }
                    .buttonStyle(.glassProminent)
                }
            } else {
                HStack(spacing: 8) {
                    if state.generating {
                        ProgressView().controlSize(.small)
                        Text("正在生成…")
                    } else if let status = state.status {
                        Label(status, systemImage: state.failed ? "exclamationmark.circle" : "checkmark.circle")
                            .foregroundStyle(state.failed ? Color.red : Color.secondary)
                    } else {
                        Text("仅向配置的模型服务发送所选期间的完成记录。")
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("模型设置", systemImage: "gear", action: openSettings)
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("复制", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(currentDraft, forType: .string)
                        state.status = "已复制"
                        state.failed = false
                    }
                    .disabled(currentDraft.trimmed.isEmpty || state.generating)
                    if let request = state.request {
                        Button("取消") { request.cancel() }
                    } else {
                        Button("生成\(state.kind.rawValue)", systemImage: "sparkles") {
                            if currentDraft.trimmed.isEmpty { generate() }
                            else { state.confirmReplace = true }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(count == 0)
                    }
                }
            }
        }
        .onChange(of: period) {
            state.status = nil
            state.confirmReplace = false
        }
    }

    private func move(_ amount: Int) {
        state.date = WorkCalendar.move(interval.start, by: amount, component: state.kind.component)
    }

    private func generate() {
        let period = period
        let material = store.reportMaterial(in: interval)
        let dates = rangeLabel
        let reportKind = state.kind.rawValue
        let chosenModel = model
        let apiAddress = address
        guard !material.isEmpty else { return }
        state.status = nil
        state.generating = true
        state.request = Task {
            defer { state.generating = false; state.request = nil }
            do {
                let endpoint = try ModelEndpoint(apiAddress)
                let key = try await ModelSettings.readKey(for: endpoint)
                try Task.checkCancellation()
                let text = try await ModelAPI(endpoint: endpoint).report(key: key, model: chosenModel, kind: reportKind,
                                                                        dates: dates, material: material)
                try Task.checkCancellation()
                state.drafts[period] = text
                state.status = "草稿已生成"
                state.failed = false
            } catch {
                if !Task.isCancelled {
                    state.status = error.localizedDescription
                    state.failed = true
                }
            }
        }
    }
}

@MainActor @Observable
final class ModelPageState {
    var address = ModelEndpoint.defaultAddress
    var chosenModel = ModelSettings.defaultModel
    var key = ""
    var models: [String] = []
    var busy = false
    var loaded = false
    var loading = false
    var status: String?
    var failed = false

    var keyEdited = false
    var savedEndpoint: ModelEndpoint?
    var savedKey = ""
}

struct ModelWorkspace: View {
    @AppStorage(ModelSettings.addressKey) private var savedAddress = ModelEndpoint.defaultAddress
    @AppStorage(ModelSettings.modelKey) private var savedModel = ModelSettings.defaultModel
    @Bindable var state: ModelPageState

    private var editingDisabled: Bool { !state.loaded || state.busy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("模型服务").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("支持兼容 OpenAI Chat Completions 的服务。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("API 地址").font(.headline)
                    TextField("API 地址", text: Binding(get: { state.address }, set: { changeAddress($0) }),
                              prompt: Text("https://example.com/v1"))
                        .textFieldStyle(.roundedBorder)
                    Text("使用服务提供的 API 地址，包含版本路径（如 /v1）。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(editingDisabled)
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key").font(.headline)
                    HStack(spacing: 8) {
                        SecureField("API Key", text: Binding(get: { state.key }, set: { editKey($0) }),
                                    prompt: Text("服务无需认证时可留空"))
                            .textFieldStyle(.roundedBorder)
                        Button("粘贴", systemImage: "doc.on.clipboard", action: pasteKey)
                            .help("从剪贴板粘贴 API Key")
                    }
                    Text("密钥按地址分别保存在此 Mac 的钥匙串中。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(editingDisabled)
                VStack(alignment: .leading, spacing: 6) {
                    Text("模型 ID").font(.headline)
                    HStack {
                        TextField("模型 ID", text: $state.chosenModel)
                            .textFieldStyle(.roundedBorder)
                        Menu("选择模型") {
                            Button("获取模型列表", action: refreshModels)
                            if !state.models.isEmpty { Divider() }
                            ForEach(state.models, id: \.self) { name in Button(name) { state.chosenModel = name } }
                        }
                        .fixedSize()
                    }
                }
                .disabled(editingDisabled)
                Divider()
                HStack(spacing: 8) {
                    if state.loading || state.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("测试连接", action: test)
                        .disabled(editingDisabled || state.address.trimmed.isEmpty || state.chosenModel.trimmed.isEmpty)
                    Button("保存设置", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(editingDisabled || state.address.trimmed.isEmpty || state.chosenModel.trimmed.isEmpty)
                }
                if let status = state.status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(state.failed ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(3)
        }
        .task { loadSettings() }
    }

    private func loadSettings() {
        guard !state.loaded, !state.loading else { return }
        state.loading = true
        state.address = savedAddress
        state.chosenModel = savedModel
        Task {
            defer {
                state.loaded = true
                state.loading = false
            }
            do {
                let endpoint = try ModelEndpoint(savedAddress)
                state.savedEndpoint = endpoint
                state.savedKey = try await ModelSettings.readKey(for: endpoint)
                state.key = state.savedKey
            } catch {
                showStatus(error.localizedDescription, failed: true)
            }
        }
    }

    private func changeAddress(_ address: String) {
        let previous = try? ModelEndpoint(state.address)
        state.address = address
        let next = try? ModelEndpoint(address)
        guard previous != next else { return }
        state.key = next == state.savedEndpoint ? state.savedKey : ""
        state.keyEdited = false
        state.models = []
        state.status = nil
    }

    private func editKey(_ key: String) {
        state.key = key
        state.keyEdited = true
    }

    private func pasteKey() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmed, !text.isEmpty else {
            showStatus("剪贴板里没有可粘贴的文本", failed: true)
            return
        }
        editKey(text)
        showStatus("已粘贴 API Key")
    }

    private func save() {
        let editedKey = state.keyEdited ? state.key.trimmed : nil
        let model = state.chosenModel.trimmed
        perform { endpoint in
            let key: String
            if let editedKey {
                try await ModelSettings.writeKey(editedKey, for: endpoint)
                key = editedKey
            } else {
                key = try await ModelSettings.readKey(for: endpoint)
            }
            savedAddress = endpoint.address
            savedModel = model
            state.address = endpoint.address
            state.chosenModel = model
            state.savedEndpoint = endpoint
            state.savedKey = key
            state.key = key
            state.keyEdited = false
            showStatus("设置已保存")
        }
    }

    private func test() {
        let model = state.chosenModel.trimmed
        perform(status: "正在测试模型…") { endpoint in
            let key = try await requestKey(for: endpoint)
            try await ModelAPI(endpoint: endpoint).test(key: key, model: model)
            showStatus("已连接，模型可用")
        }
    }

    private func refreshModels() {
        perform(status: "正在获取模型…") { endpoint in
            let key = try await requestKey(for: endpoint)
            state.models = try await ModelAPI(endpoint: endpoint).models(key: key)
            showStatus(state.models.isEmpty ? "服务未返回可选模型，可手动填写模型 ID。" : "模型列表已更新")
        }
    }

    private func requestKey(for endpoint: ModelEndpoint) async throws -> String {
        if state.keyEdited { return state.key.trimmed }
        return try await ModelSettings.readKey(for: endpoint)
    }

    private func showStatus(_ message: String, failed: Bool = false) {
        state.status = message
        state.failed = failed
    }

    private func perform(status: String? = nil, operation: @escaping @MainActor (ModelEndpoint) async throws -> Void) {
        let address = state.address
        state.busy = true
        state.status = status
        state.failed = false
        Task {
            defer { state.busy = false }
            do {
                try await operation(ModelEndpoint(address))
            } catch {
                showStatus(error.localizedDescription, failed: true)
            }
        }
    }
}
