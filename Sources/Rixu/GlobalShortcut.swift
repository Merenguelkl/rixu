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
        unregister()
        recording = true
        message = nil
    }

    func cancelRecording() {
        guard recording else { return }
        recording = false
        _ = register(key)
    }

    func reset() { change(to: .standard) }

    func capture(_ event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return false }
        if event.isARepeat { return true }
        if event.keyCode == kVK_Escape && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            cancelRecording()
        } else if let next = ShortcutKey(event: event) {
            change(to: next)
        } else {
            message = "请按下包含 Command、Option 或 Control 的组合键。"
        }
        return true
    }

    private func change(to next: ShortcutKey) {
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
