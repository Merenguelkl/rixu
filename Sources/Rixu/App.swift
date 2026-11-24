import AppKit
import SwiftUI

@main
enum Rixu {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

enum Workspace: String {
    case calendar = "日历"
    case reports = "工作报告"
    case settings = "模型设置"
    case appearance = "外观"
}

extension Notification.Name {
    static let rixuPanelOpened = Self("RixuPanelOpened")
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store: TaskStore
    private var item: NSStatusItem?
    private enum PanelOrigin { case menuBar, dock }

    private var panel: MenuPanel?
    private var panelOrigin: PanelOrigin?
    private var panelPresentedAt: TimeInterval = 0
    private var outsideMonitor: Any?

    override init() {
        let directory = ProcessInfo.processInfo.environment["RIXU_DATA_DIRECTORY"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? URL.applicationSupportDirectory.appending(path: "Rixu", directoryHint: .isDirectory)
        store = TaskStore(file: directory.appending(path: "tasks.json"))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "Rixu", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出日序", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = Self.statusImage()
            button.toolTip = "日序 · 待办与每日记录"
            button.setAccessibilityLabel("日序")
            button.target = self
            button.action = #selector(toggle)
        }
        item = status
        Task { @MainActor in
            await Task.yield()
            let point = NSEvent.mouseLocation
            let dock = dockPlacement(at: point)
            showPanel(from: dock.contains(point) ? .dock : .menuBar, at: point)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPanel(from: .dock, at: NSEvent.mouseLocation)
        return false
    }

    @objc private func toggle() {
        if panel?.isVisible == true, panelOrigin == .menuBar {
            hidePanel()
        } else {
            showPanel(from: .menuBar)
        }
    }

    private func showPanel(from origin: PanelOrigin, at point: CGPoint = NSEvent.mouseLocation) {
        let wasVisible = panel?.isVisible == true
        let frame = switch origin {
        case .menuBar: menuBarFrame()
        case .dock: dockPlacement(at: point).frame(near: point)
        }

        let windowPanel = panel ?? makePanel(frame)
        windowPanel.setFrame(frame, display: wasVisible)
        panelOrigin = origin
        panelPresentedAt = ProcessInfo.processInfo.systemUptime
        windowPanel.makeKeyAndOrderFront(nil)
        if !wasVisible {
            NotificationCenter.default.post(name: .rixuPanelOpened, object: windowPanel)
        }
        item?.button?.highlight(origin == .menuBar)
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let clickedAt = event.timestamp
                Task { @MainActor in
                    guard let self, clickedAt >= self.panelPresentedAt else { return }
                    self.hidePanel()
                }
            }
        }
    }

    private func menuBarFrame() -> CGRect {
        let button = item?.button
        let window = button?.window
        let visible = (window?.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        if let button, let window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            return PanelPlacement.menuBar(anchor: anchor, in: visible)
        }
        let anchor = CGRect(x: visible.maxX - 48, y: visible.maxY, width: 0, height: 0)
        return PanelPlacement.menuBar(anchor: anchor, in: visible)
    }

    private func dockPlacement(at point: CGPoint) -> DockPlacement {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let preferences = UserDefaults(suiteName: "com.apple.dock")
        let edge = preferences?.string(forKey: "orientation").flatMap(DockEdge.init(rawValue:)) ?? .bottom
        let tiles = preferences?.double(forKey: "tilesize") ?? 0
        let magnifiedTiles = preferences?.bool(forKey: "magnification") == true
            ? preferences?.double(forKey: "largesize") ?? 0 : 0
        let fallback = CGRect(x: 0, y: 0, width: 800, height: 600)
        return DockPlacement(edge: edge, screen: screen?.frame ?? fallback,
                             workArea: screen?.visibleFrame ?? fallback,
                             tileSize: tiles > 0 ? tiles : 48, magnifiedTileSize: magnifiedTiles)
    }

    private static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 17), flipped: false) { _ in
            NSColor.black.setStroke()
            let mark = NSBezierPath()
            mark.lineWidth = 1.8
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            mark.move(to: NSPoint(x: 2.8, y: 9.2))
            mark.line(to: NSPoint(x: 6.9, y: 5.2))
            mark.line(to: NSPoint(x: 14.2, y: 12.8))
            mark.stroke()
            let line = NSBezierPath()
            line.lineWidth = 1.2
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 6.9, y: 2.2))
            line.line(to: NSPoint(x: 14.2, y: 2.2))
            line.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "日序"
        return image
    }

    private func makePanel(_ frame: NSRect) -> MenuPanel {
        let windowPanel = MenuPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        windowPanel.isOpaque = false
        windowPanel.backgroundColor = .clear
        // The glass supplies its own edge. A window shadow also outlines the rectangular frame.
        windowPanel.hasShadow = false
        windowPanel.level = .popUpMenu
        windowPanel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        windowPanel.hidesOnDeactivate = false
        windowPanel.delegate = self
        windowPanel.setAccessibilityLabel("日序菜单栏面板")
        windowPanel.onEscape = { [weak self] in self?.hidePanel() }
        let surface = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let glass = NSGlassEffectView(frame: surface.bounds)
        glass.cornerRadius = 24
        let content = MenuContent(store: store, quit: { NSApp.terminate(nil) }, applyTransparency: { [weak glass] value in
            if let glass { value.apply(to: glass) }
        })
        let host = NSHostingView(rootView: content)
        glass.contentView = host
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            host.topAnchor.constraint(equalTo: glass.topAnchor),
            host.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        // Clip the glass's translucent halo to the same rounded outline as the panel.
        surface.wantsLayer = true
        surface.layer?.cornerRadius = glass.cornerRadius
        surface.layer?.cornerCurve = .continuous
        surface.layer?.masksToBounds = true
        glass.autoresizingMask = [.width, .height]
        surface.addSubview(glass)
        windowPanel.contentView = surface
        panel = windowPanel
        return windowPanel
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel === notification.object as? NSWindow else { return }
        hidePanel()
    }

    private func hidePanel() {
        panelOrigin = nil
        panel?.orderOut(nil)
        item?.button?.highlight(false)
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
    }
}

private final class MenuPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector?
            switch key {
            case "a": action = #selector(NSResponder.selectAll(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "x": action = #selector(NSText.cut(_:))
            default: action = nil
            }
            if let action, firstResponder?.tryToPerform(action, with: nil) == true { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53,
           (firstResponder as? NSTextInputClient)?.hasMarkedText() != true {
            onEscape?()
            return
        }
        if event.type == .keyDown, event.modifierFlags.contains(.command),
           performKeyEquivalent(with: event) { return }
        super.sendEvent(event)
    }
}
