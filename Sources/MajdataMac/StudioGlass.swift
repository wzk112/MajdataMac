import SwiftUI
import AppKit

enum StudioPalette {
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.04, green: 0.17, blue: 0.21, alpha: 1) : .white
    })
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.49, green: 0.83, blue: 0.89, alpha: 1)
            : NSColor(red: 0.04, green: 0.36, blue: 0.44, alpha: 1)
    })
}

/// Neutral pearl/graphite lighting gives clear system glass depth without tinting note colours.
struct StudioBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                LinearGradient(colors: scheme == .dark
                    ? [Color(red: 0.10, green: 0.11, blue: 0.12), Color(red: 0.18, green: 0.19, blue: 0.20), Color(red: 0.09, green: 0.10, blue: 0.11)]
                    : [Color(red: 0.87, green: 0.88, blue: 0.87), Color(red: 0.96, green: 0.95, blue: 0.93), Color(red: 0.81, green: 0.84, blue: 0.84)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.background(StudioWindowSurface()).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Make the native title bar and window backing transparent as well as the SwiftUI content.
private struct StudioWindowSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowSurfaceAnchor { WindowSurfaceAnchor() }
    func updateNSView(_ view: WindowSurfaceAnchor, context: Context) { view.configure() }
}

private final class WindowSurfaceAnchor: NSView {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
    func configure() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}

private struct StudioGlassPanel: ViewModifier {
    var radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content.clipShape(RoundedRectangle(cornerRadius: radius))
                    .background(.background, in: RoundedRectangle(cornerRadius: radius))
            } else {
                content.clipShape(RoundedRectangle(cornerRadius: radius))
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: radius))
            }
        }
    }
}

extension View {
    func studioGlass(_ radius: CGFloat = 20) -> some View { modifier(StudioGlassPanel(radius: radius)) }
}

enum StudioMotion {
    static let panel = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.30)
    static let selection = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
}

struct StudioToolbarIcon: View {
    var title: String
    var symbol: String
    var body: some View {
        Image(systemName: symbol).renderingMode(.original).symbolRenderingMode(.palette)
            .foregroundStyle(StudioPalette.accent).font(.system(size: 14, weight: .medium))
            .frame(width: 32, height: 32).contentShape(Circle())
            .accessibilityLabel(title)
            .environment(\.controlActiveState, .key)
    }
}

struct StudioToolbarButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { StudioToolbarIcon(title: title, symbol: symbol) }
            .buttonStyle(.plain).help(title)
    }
}

/// Form-free glass cards still align switches at the trailing edge.
struct StudioSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.accessibilityHidden(true)
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { configuration.label }.labelsHidden().toggleStyle(.switch)
        }
    }
}
