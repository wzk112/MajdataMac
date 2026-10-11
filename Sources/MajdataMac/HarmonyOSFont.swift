import SwiftUI
import CoreText

/// Unmodified official font files are embedded with their original license.
@MainActor enum HarmonyOSFont {
    @MainActor private struct Face {
        let graphicsFont: CGFont
        let name: String
        init(_ weight: String) {
            let url = StudioModel.resourceURL.appendingPathComponent("Fonts/HarmonyOS_Sans_SC_" + weight + ".ttf") as CFURL
            guard let provider = CGDataProvider(url: url), let font = CGFont(provider),
                  let name = font.postScriptName as String? else { fatalError("Bundled HarmonyOS Sans font is invalid") }
            graphicsFont = font
            self.name = name
            CTFontManagerRegisterFontsForURL(url, .process, nil)
        }
    }
    private static let regular = Face("Regular")
    private static let bold = Face("Bold")
    static func coreText(size: CGFloat, bold useBold: Bool = false) -> CTFont {
        CTFontCreateWithGraphicsFont((useBold ? bold : regular).graphicsFont, size, nil, nil)
    }
    static func swiftUI(size: CGFloat, bold useBold: Bool = false) -> Font {
        .custom((useBold ? bold : regular).name, size: size)
    }
}
