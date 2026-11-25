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
                }
            case .appearance:
                AppearanceWorkspace(transparency: $transparency)
            case .models:
                ModelWorkspace(state: models)
            }
        }
    }
}
