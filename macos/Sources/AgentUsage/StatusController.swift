import AgentUsageCore
import AppKit
import Combine
import SwiftUI

/// The menu bar item and the panel under it.
final class StatusController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let window: PanelWindow
    private var keyMonitor: Any?
    private var outsideMonitor: Any?
    private var tickTimer: Timer?
    private var changes: AnyCancellable?
    private var resizeScheduled = false
    private var closedAt = Date.distantPast

    init(model: AppModel) {
        self.model = model
        window = PanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        window.contentView = NSHostingView(rootView: PanelWindowView(model: model.panel))
        window.delegate = self

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
            button.setAccessibilityTitle("Agent usage")
        }
        model.onRecordsChange = { [weak self] in self?.updateMenuBar() }
        model.onNotice = { [weak self] in self?.open() }
        changes = model.panel.objectWillChange.sink { [weak self] _ in self?.scheduleResize() }
        updateMenuBar()
    }

    // ------------------------------------------------------------ menu bar

    /// The robot and the fullest limit (the session limit once it reaches the
    /// setting), red from 90%, faded while the numbers are from an earlier
    /// check. The robot turns orange while an agent session waits for you and
    /// green once one is done; red then stays with the number. Unlike on GNOME
    /// the robot always shows, so there's something to click before the first
    /// scan.
    func updateMenuBar() {
        guard let button = item.button else {
            return
        }
        let providers = model.providers
        let alarming = Panel.menuBarAlarming(providers)
        button.image = Assets.robot
        button.contentTintColor = model.session.map(Theme.sessionNS) ?? (alarming ? Theme.urgentNS : nil)
        let sessionFrom = UserDefaults.standard.integer(forKey: Settings.sessionThreshold)
        guard let text = Panel.menuBarText(providers, sessionFrom: sessionFrom) else {
            button.title = ""
            button.imagePosition = .imageOnly
            return
        }
        var color = alarming ? Theme.urgentNS : NSColor.labelColor
        if Panel.menuBarStale(providers) {
            color = color.withAlphaComponent(Panel.staleOpacity)
        }
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: color,
        ])
    }

    /// Left click opens the panel, right click (or Control-click) opens the
    /// agent, middle click refreshes: the same as Omarchy's bar icon.
    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        switch event?.type {
        case .rightMouseUp?:
            close()
            model.launchAgent()
        case .otherMouseUp?:
            model.runUpdate(.force)
        default:
            if event?.modifierFlags.contains(.control) == true {
                close()
                model.launchAgent()
            } else {
                toggle()
            }
        }
    }

    // ------------------------------------------------------------ panel

    private func toggle() {
        // A click on the icon first takes the focus away from the panel, which
        // closes it; that click shouldn't open it straight back up.
        if window.isVisible {
            close()
        } else if Date().timeIntervalSince(closedAt) > 0.3 {
            open()
        }
    }

    func open() {
        model.panelOpened()
        resize()
        window.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else {
                return event
            }
            return self.handleKey(event) ? nil : event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.model.tick() }
    }

    func close() {
        guard window.isVisible else {
            return
        }
        window.orderOut(nil)
        closedAt = Date()
        [keyMonitor, outsideMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        keyMonitor = nil
        outsideMonitor = nil
        tickTimer?.invalidate()
        tickTimer = nil
        model.panelClosed()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// ←/→ (or h/l) switch agents, r refreshes, Esc closes.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch (event.keyCode, event.charactersIgnoringModifiers?.lowercased()) {
        case (53, _):
            close()
        case (123, _), (_, "h"?):
            model.step(-1)
        case (124, _), (_, "l"?):
            model.step(1)
        case (_, "r"?):
            model.runUpdate(.force)
        default:
            return false
        }
        return true
    }

    private func scheduleResize() {
        guard window.isVisible, !resizeScheduled else {
            return
        }
        resizeScheduled = true
        // objectWillChange fires before the change lands.
        DispatchQueue.main.async { [weak self] in
            self?.resizeScheduled = false
            self?.resize()
        }
    }

    /// Fits the panel to its content, under the icon, and lets it scroll once
    /// it's taller than the screen below the menu bar.
    private func resize() {
        guard let button = item.button, let buttonWindow = button.window else {
            return
        }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let content = NSHostingView(rootView: PanelContent(model: model.panel)).fittingSize.height
        let room = max(200, anchor.minY - visible.minY - 12)
        let height = min(content, room)
        let viewport: CGFloat? = content > room ? room : nil
        if model.panel.viewport != viewport {
            model.panel.viewport = viewport
        }

        let width = Theme.panelWidth
        let x = min(max(anchor.minX, visible.minX + 4), visible.maxX - width - 4)
        window.setFrame(NSRect(x: x, y: anchor.minY - height - 4, width: width, height: height), display: true)
    }
}

/// A borderless panel that takes the keyboard without bringing the app to the
/// front, like a menu.
final class PanelWindow: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
}
