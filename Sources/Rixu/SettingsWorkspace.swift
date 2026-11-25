import SwiftUI

enum SettingsSection: String, CaseIterable {
    case general = "通用"
    case appearance = "外观"
    case models = "模型"
}

struct SettingsWorkspace: View {
    @Binding var section: SettingsSection
    @Binding var hoverEnabled: Bool
    @Binding var transparency: GlassTransparency
    let models: ModelPageState
    let shortcut: GlobalShortcut

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("设置类别", selection: $section) {
                ForEach(SettingsSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch section {
            case .general:
                ScrollView {
                    VStack(spacing: 12) {
                        Toggle(isOn: $hoverEnabled) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("悬停显示面板").font(.headline)
                                Text("在菜单栏图标上停留约 0.3 秒打开面板。移入面板会保持打开，离开图标和面板后短暂延迟收起。点击图标也可开关面板。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .toggleStyle(.switch)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12))
                        shortcutSettings
                    }
                }
            case .appearance:
                AppearanceWorkspace(transparency: $transparency)
            case .models:
                ModelWorkspace(state: models)
            }
        }
    }

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("全局快捷键").font(.headline)
                Spacer()
                Text(shortcut.key.display).monospaced().foregroundStyle(.secondary)
            }
            Text(shortcut.recording ? "按下新的组合键，或按 Esc 取消。" : "在任何应用中打开日序。⌘R 常用于刷新页面。")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(shortcut.recording ? "取消录制" : "录制快捷键") {
                    if shortcut.recording { shortcut.cancelRecording() }
                    else { shortcut.beginRecording() }
                }
                Button("恢复默认") { shortcut.reset() }
                    .disabled(shortcut.key == .standard && shortcut.message == nil)
            }
            if let message = shortcut.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 12))
        .onDisappear { shortcut.cancelRecording() }
    }
}
