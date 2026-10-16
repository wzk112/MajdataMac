import SwiftUI
import AppKit

/// Isolate each panel's glass compositor inside a native clipping view. SwiftUI's
/// clipped() alone does not contain glass promoted into an ancestor glass container.
struct StudioPanelReveal<Content: View>: View, Animatable {
    nonisolated var progress: Double
    var fullWidth: Double
    var alignment: Alignment
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let width = fullWidth * min(1, max(0, progress))
        PanelClipHost(fullWidth: fullWidth, trailing: alignment == .trailing, hidden: width < 0.5) {
            GlassEffectContainer(spacing: 4) { content() }
                .accessibilityElement(children: .contain)
                .tint(StudioPalette.accent)
                .environment(\.controlActiveState, .key)
                .environment(\.colorScheme, colorScheme)
                .transaction { $0.animation = nil }
        }
        .frame(width: width)
    }
}

private struct PanelClipHost<Content: View>: NSViewRepresentable {
    var fullWidth: Double
    var trailing: Bool
    var hidden: Bool
    @ViewBuilder var content: () -> Content
    func makeNSView(context: Context) -> PanelClippingView<Content> {
        PanelClippingView(rootView: content())
    }
    func updateNSView(_ view: PanelClippingView<Content>, context: Context) {
        view.host.rootView = content()
        view.fullWidth = fullWidth
        view.trailing = trailing
        if hidden, let responder = view.window?.firstResponder as? NSView, responder.isDescendant(of: view.host) {
            view.window?.makeFirstResponder(nil)
        }
        view.host.isHidden = hidden
        view.needsLayout = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PanelClippingView<Content>, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? fullWidth, height: proposal.height ?? 600)
    }
}

final class PanelClippingView<Content: View>: NSView {
    let host: NSHostingView<Content>
    var fullWidth = 0.0
    var trailing = false
    init(rootView: Content) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("studio-panel-clip")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        host.sizingOptions = []
        addSubview(host)
        host.setAccessibilityParent(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityChildren() -> [Any]? {
        host.isHidden ? [] : [host]
    }
    override func layout() {
        super.layout()
        host.frame = NSRect(x: trailing ? bounds.width - fullWidth : 0, y: 0,
                            width: fullWidth, height: bounds.height)
    }
}
