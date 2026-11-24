import AppKit
import SwiftUI

enum GlassTransparency: Int, CaseIterable {
    case lowest
    case low
    case standard
    case high
    case highest

    static let preferenceKey = "appearance.glass-transparency"

    var label: String {
        switch self {
        case .lowest: "最低"
        case .low: "较低"
        case .standard: "标准"
        case .high: "较高"
        case .highest: "最高"
        }
    }

    @MainActor func apply(to glass: NSGlassEffectView) {
        switch self {
        case .lowest:
            glass.style = .regular
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.60)
        case .low:
            glass.style = .regular
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.30)
        case .standard:
            glass.style = .regular
            glass.tintColor = nil
        case .high:
            glass.style = .clear
            glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.24)
        case .highest:
            glass.style = .clear
            glass.tintColor = nil
        }
    }
}

struct AppearanceWorkspace: View {
    @Binding var transparency: GlassTransparency

    private var level: Binding<Double> {
        Binding(get: { Double(transparency.rawValue) }, set: {
            transparency = GlassTransparency(rawValue: Int($0)) ?? .standard
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("玻璃透明度").font(.headline)
                Spacer()
                Text(transparency.label).font(.callout).foregroundStyle(.secondary)
            }
            Slider(value: level, in: 0...4, step: 1)
                .accessibilityLabel("玻璃透明度")
                .accessibilityValue(transparency.label)
            HStack {
                Text("更实")
                Spacer()
                Text("更通透")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            HStack {
                Text("调整时可直接预览面板。").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("恢复标准") { transparency = .standard }
                    .disabled(transparency == .standard)
            }
            Spacer()
        }
        .padding(3)
    }
}
