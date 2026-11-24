import SwiftUI

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct IconButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: size, height: size)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct SectionName: View {
    let title: String
    let count: Int
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).accessibilityHidden(true)
            }
            Text(title).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(count, format: .number)
                .monospacedDigit()
                .accessibilityLabel("\(count) 项")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

struct DoneLabel: View {
    let entry: DoneEntry
    var showsTime = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if case let .subtask(_, parent) = entry.source {
                Text(parent).font(.caption).foregroundStyle(.secondary)
            } else if showsTime, entry.source != .manual {
                Text(WorkCalendar.label(entry.date, "HH:mm"))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowHighlight: ViewModifier {
    var baseOpacity = 0.045
    var radius: CGFloat = 11
    var tint = Color.accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(.primary.opacity(baseOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(tint.opacity(hovered ? 0.13 : 0))
                    }
            }
            .contentShape(.rect(cornerRadius: radius))
            .onHover { inside in
                withAnimation(reduceMotion ? nil : .easeOut(duration: inside ? 0.16 : 0.20)) {
                    hovered = inside
                }
            }
    }
}

struct DeleteConfirmation: View {
    let message: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("取消", action: cancel)
            Button("确认", role: .destructive, action: confirm)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }
}
