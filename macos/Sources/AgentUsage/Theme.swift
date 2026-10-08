import AgentUsageCore
import AppKit
import AudioToolbox
import CoreText
import SwiftUI

/// Omarchy's Agents panel in its Kanagawa theme, as the GNOME extension's
/// stylesheet.css draws it. Sizes are the stylesheet's, with its points
/// turned into macOS points (CSS pixels): 10pt there is 13.3 here.
enum Theme {
    static let background = Color(hex: 0x1F1F28)
    static let foreground = Color(hex: 0xDCD7BA)
    static let dim = Color(hex: 0x8E8B78)
    static let urgent = Color(hex: 0xC34043)
    static let stale = Color(hex: 0xC0A36E)

    static let urgentNS = NSColor(hex: 0xC34043)
    /// The robot while a session waits for you, and once one is done:
    /// Kanagawa's wave colours on a dark menu bar, its lotus (light theme)
    /// colours on a light one, where the wave ones are too pale to read.
    static let waitingNS = barNS("agent-usage-waiting", light: 0xCC6D00, dark: 0xFFA066)
    static let readyNS = barNS("agent-usage-ready", light: 0x6F894E, dark: 0x98BB6C)
    /// The percentage while the numbers are from an earlier check: the bar's
    /// text colour at GNOME's stale opacity.
    static let fadedNS = NSColor(name: "agent-usage-faded") {
        ($0.isDark ? NSColor.white : NSColor.black).withAlphaComponent(Panel.staleOpacity)
    }

    /// A menu bar colour that resolves when the bar draws it. The bar is light
    /// or dark with the wallpaper behind it, not with the system setting, and
    /// each screen's bar decides for itself, so a fixed colour can't suit them
    /// all. A dynamic one is resolved per bar, as labelColor is.
    static func barNS(_ name: String, light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: name) { $0.isDark ? NSColor(hex: dark) : NSColor(hex: light) }
    }

    static func sessionNS(_ session: TopBarSession) -> NSColor {
        switch session {
        case .waiting: return waitingNS
        case .ready: return readyNS
        }
    }

    /// The panel's content width; the padding comes on top, as in the GNOME
    /// panel, and the 1-point border sits inside the padding.
    static let contentWidth: CGFloat = 380
    static let padding: CGFloat = 16
    static var panelWidth: CGFloat { contentWidth + 2 * padding }

    static func points(_ cssPoints: CGFloat) -> CGFloat {
        cssPoints * 4 / 3
    }

    static func font(_ cssPoints: CGFloat, bold: Bool = false) -> Font {
        Font.custom(bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular", size: points(cssPoints))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// This colour as `appearance` draws it, fixed: for drawing it somewhere
    /// other than the menu bar, like the snapshots.
    func resolved(in appearance: NSAppearance) -> NSColor {
        var color = self
        appearance.performAsCurrentDrawingAppearance { color = NSColor(cgColor: cgColor) ?? self }
        return color
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// The icons and fonts that build-app.sh puts in the app's Resources folder.
enum Assets {
    static func registerFonts() {
        let fonts = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in fonts {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func icon(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "pdf").flatMap(NSImage.init(contentsOf:))
    }

    /// The robot, as a template image: macOS colours it for the menu bar.
    static let robot: NSImage = {
        let image = icon("agent-usage-symbolic") ?? NSImage(systemSymbolName: "cpu", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    /// Nothing, at the robot's size: what the menu bar button shows while the
    /// robot's pop stands in for it.
    static let blankRobot = NSImage(size: robot.size, flipped: false) { _ in true }

    private static var tintedRobots: [NSColor: NSImage] = [:]

    /// The robot for the menu bar: the template one, which macOS colours to
    /// match the menu bar, or a copy painted in `tint`. The menu bar draws a
    /// template image with a `contentTintColor` in black, whatever the colour
    /// (FB8530353, since macOS 11), so the colour goes into the image itself,
    /// which the menu bar draws as it is.
    static func robot(_ tint: NSColor?) -> NSImage {
        guard let tint else {
            return robot
        }
        if let image = tintedRobots[tint] {
            return image
        }
        let template = robot
        // Drawn when it's shown, so it stays sharp on any screen, and in the
        // appearance of the bar that shows it: a dynamic tint resolves here.
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        // Not cached, or one bar's colour could be kept for another's.
        image.cacheMode = .never
        image.isTemplate = false
        tintedRobots[tint] = image
        return image
    }

    /// An agent's logo for the panel header, or the robot for agents without
    /// one.
    static func logo(_ id: String) -> (image: NSImage, template: Bool) {
        if let image = icon(id) {
            return (image, false)
        }
        return (robot, true)
    }
}

/// The robot's sounds, Resources/Sounds/waiting.wav and ready.wav, the GNOME
/// extension's. Played as system sounds, which stay quiet with "Play user
/// interface sound effects" off, as GNOME's do with alert sounds off.
enum Sounds {
    private static var loaded: [TopBarSession: SystemSoundID] = [:]

    static func play(_ alert: TopBarSession) {
        if loaded[alert] == nil, let url = Bundle.main.url(forResource: alert.rawValue, withExtension: "wav", subdirectory: "Sounds") {
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError {
                loaded[alert] = id
            } else {
                Log.write("couldn't load the \(alert.rawValue) sound")
            }
        }
        if let id = loaded[alert] {
            AudioServicesPlaySystemSound(id)
        }
    }
}
