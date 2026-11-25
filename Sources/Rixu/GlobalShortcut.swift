import AppKit
import Carbon

struct ShortcutKey: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let standard = ShortcutKey(keyCode: UInt32(kVK_ANSI_R),
                                      modifiers: UInt32(controlKey | optionKey | cmdKey), key: "R")
    var display: String {
        let symbols = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return symbols.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    var commonAction: String? {
        let command = UInt32(cmdKey)
        let shifted = UInt32(cmdKey | shiftKey)
        return switch (modifiers, key) {
        case (command, "R"), (shifted, "R"): "刷新页面"
        case (command, "Q"): "退出应用"
        case (command, "W"): "关闭窗口或标签页"
        case (command, "T"), (shifted, "T"): "新建或重新打开标签页"
        case (command, "N"): "新建窗口或文稿"
        case (command, "S"), (shifted, "S"): "保存文稿或另存为"
        case (command, "C"): "复制"
        case (command, "V"): "粘贴"
        case (command, "X"): "剪切"
        case (command, "Z"), (shifted, "Z"): "撤销或重做"
        case (command, "A"): "全选"
        case (command, "F"): "查找"
        case (command, "P"): "打印"
        case (command, "O"): "打开文件"
        case (command, "H"): "隐藏当前应用"
        case (command, "M"): "最小化窗口"
        case (command, "⇥"), (shifted, "⇥"): "切换应用"
        case (command, "空格"): "打开聚焦搜索"
        case (command, ","): "打开应用设置"
        case (shifted, _) where [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(Int(keyCode)): "截屏"
        case (UInt32(cmdKey | optionKey), "Esc"): "打开强制退出窗口"
        default: nil
        }
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let mapping: [(NSEvent.ModifierFlags, Int)] = [(.command, cmdKey), (.option, optionKey),
                                                      (.control, controlKey), (.shift, shiftKey)]
        let modifiers = mapping.reduce(UInt32(0)) { $0 | (flags.contains($1.0) ? UInt32($1.1) : 0) }
        let symbols: [Int: String] = [
            kVK_Space: "空格", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
        ]
        let key = symbols[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
    }
}

@MainActor @Observable
final class GlobalShortcut {
    static let preferenceKey = "shortcut.open-panel"
    private static let signature: OSType = 0x5269_7875

    private(set) var key = ShortcutKey.standard
    private(set) var recording = false
    private(set) var pendingConflict: ShortcutKey?
    private(set) var message: String?
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var reference: EventHotKeyRef?
    @ObservationIgnored private var onPress: (() -> Void)?

    func start(onPress: @escaping () -> Void) {
        self.onPress = onPress
        if let data = UserDefaults.standard.data(forKey: Self.preferenceKey),
           let saved = try? JSONDecoder().decode(ShortcutKey.self, from: data) {
            key = saved
        }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            var token = EventHotKeyID()
            guard let event, let pointer,
                  GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &token) == noErr,
                  token.signature == GlobalShortcut.signature, token.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(pointer).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            message = "无法启用全局快捷键。"
            return
        }
        _ = register(key)
    }

    func stop() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        onPress = nil
    }

    func beginRecording() {
        pendingConflict = nil
        unregister()
        recording = true
        message = nil
    }

    func cancelRecording() {
        pendingConflict = nil
        guard recording else { return }
        recording = false
        _ = register(key)
    }

    func reset() { change(to: .standard) }

    func acceptConflict() {
        guard let pendingConflict else { return }
        change(to: pendingConflict)
    }

    func capture(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let cancel = event.keyCode == kVK_Escape && modifiers.isEmpty
        if let pendingConflict {
            if cancel {
                cancelRecording()
                return true
            }
            return event.isARepeat && UInt32(event.keyCode) == pendingConflict.keyCode
        }
        guard recording else { return false }
        if event.isARepeat { return true }
        if cancel {
            cancelRecording()
        } else if let next = ShortcutKey(event: event) {
            if next.commonAction != nil && (next.keyCode != key.keyCode || next.modifiers != key.modifiers) {
                recording = false
                pendingConflict = next
                _ = register(key)
            } else {
                change(to: next)
            }
        } else {
            message = "请按下包含 Command、Option 或 Control 的组合键。"
        }
        return true
    }

    private func change(to next: ShortcutKey) {
        pendingConflict = nil
        unregister()
        recording = false
        if register(next) {
            key = next
            if let data = try? JSONEncoder().encode(next) {
                UserDefaults.standard.set(data, forKey: Self.preferenceKey)
            }
        } else {
            let failure = message
            if register(key) { message = failure }
        }
    }

    private func register(_ value: ShortcutKey) -> Bool {
        guard handler != nil else {
            message = "无法启用全局快捷键。"
            return false
        }
        let token = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(value.keyCode, value.modifiers, token, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &reference)
        message = status == noErr ? nil : "无法注册 \(value.display)，它可能已被其他应用占用。"
        return status == noErr
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }
}
