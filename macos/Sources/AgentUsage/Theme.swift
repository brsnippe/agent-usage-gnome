import AppKit
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

    static let urgentNS = NSColor(red: 0xC3 / 255, green: 0x40 / 255, blue: 0x43 / 255, alpha: 1)

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

    /// An agent's logo for the panel header, or the robot for agents without
    /// one.
    static func logo(_ id: String) -> (image: NSImage, template: Bool) {
        if let image = icon(id) {
            return (image, false)
        }
        return (robot, true)
    }
}
