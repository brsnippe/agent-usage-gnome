import AgentUsageCore
import AppKit
import Combine
import QuartzCore
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
    /// The robot's pop, while it runs, and the robot it stands in for.
    private var popLayer: CALayer?
    private var popRobot: NSImage?

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
        model.onSessionAlert = { [weak self] in self?.alert($0) }
        changes = model.panel.objectWillChange.sink { [weak self] _ in
            // Hover changes colour only, so the panel keeps its height.
            if self?.model.panel.hovering == false {
                self?.scheduleResize()
            }
        }
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
        let robot = Assets.robot(model.session.map(Theme.sessionNS) ?? (alarming ? Theme.urgentNS : nil))
        // A pop in one colour ends when the robot changes to another.
        if popLayer != nil, robot !== popRobot {
            stopPop()
        }
        button.image = popLayer == nil ? robot : Assets.blankRobot
        // What the colour says, for VoiceOver.
        switch model.session {
        case .waiting?: button.setAccessibilityValue("A session waits for you")
        case .ready?: button.setAccessibilityValue("A session is done")
        case nil: button.setAccessibilityValue(nil)
        }
        let sessionFrom = UserDefaults.standard.integer(forKey: Settings.sessionThreshold)
        guard let text = Panel.menuBarText(providers, sessionFrom: sessionFrom) else {
            button.title = ""
            button.imagePosition = .imageOnly
            return
        }
        // The bar's text colour follows the wallpaper behind it, per screen,
        // not the system setting. Dynamic colours resolve when each bar draws
        // them; withAlphaComponent on one resolves it right away, in the app's
        // own appearance, and hands every bar the same fixed black or white.
        let stale = Panel.menuBarStale(providers)
        let color: NSColor
        if alarming {
            color = stale ? Theme.urgentNS.withAlphaComponent(Panel.staleOpacity) : Theme.urgentNS
        } else {
            color = stale ? Theme.fadedNS : .labelColor
        }
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: color,
        ])
    }

    /// A session started waiting for you, or finished its turn.
    private func alert(_ alert: TopBarSession) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Settings.sessionPop) {
            pop()
        }
        if defaults.bool(forKey: Settings.sessionSounds) {
            Sounds.play(alert)
        }
    }

    /// The robot grows and springs back, once: a layer of its own over the
    /// robot, which stands in for the button's image while it runs. Scaling
    /// the button itself would scale the percentage too, and AppKit manages
    /// the button layer's anchor and transform. The menu bar cuts off what
    /// leaves the item, so it only grows to 1.2×. Not with Reduce motion on.
    private func pop() {
        guard popLayer == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let button = item.button, let robot = button.image, !robot.isTemplate, let cell = button.cell else {
            return
        }
        button.wantsLayer = true
        guard let host = button.layer else {
            return
        }
        let scale = button.window?.backingScaleFactor ?? 2
        let layer = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Also when a change of colour ended it early, so only this pop's.
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let self, let layer, self.popLayer === layer else {
                return
            }
            self.stopPop()
            self.updateMenuBar()
        }
        layer.frame = cell.imageRect(forBounds: button.bounds)
        layer.contentsScale = scale
        layer.contentsGravity = .resizeAspect
        // In the bar's appearance, as the button draws it: the tint is dynamic.
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.contents = robot.layerContents(forContentsScale: scale)
        }
        host.addSublayer(layer)
        popLayer = layer
        popRobot = robot
        button.image = Assets.blankRobot

        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [1.0, 1.2, 0.95, 1.0]
        animation.keyTimes = [0, 0.27, 0.65, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        animation.duration = 0.45
        layer.add(animation, forKey: "pop")
        CATransaction.commit()
    }

    private func stopPop() {
        popLayer?.removeFromSuperlayer()
        popLayer = nil
        popRobot = nil
    }

    /// Left click opens the panel, right click (or Control-click) opens the
    /// agent, middle click refreshes: the same as Omarchy's bar icon. With
    /// that switched off, right click opens the panel too.
    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if event?.type == .otherMouseUp {
            model.runUpdate(.force)
        } else if rightClick && UserDefaults.standard.bool(forKey: Settings.rightClickOpensAgent) {
            close()
            model.launchAgent()
        } else {
            toggle()
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
        tickTimer = Timer.lenient(30, repeats: true) { [weak self] in self?.model.tick() }
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

    /// ←/→ (or h/l) switch agents, r refreshes, Esc closes, q (and ⌘Q)
    /// quits.
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
        case (_, "q"?):
            NSApp.terminate(nil)
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
