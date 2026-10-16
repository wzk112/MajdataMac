import SwiftUI

/// Keep the panel alive and interpolate its actual layout width. A move transition
/// plus an animated HStack used to move it twice and leave the AppKit editor behind.
struct StudioPanelReveal<Content: View>: View, Animatable {
    nonisolated var progress: Double
    var fullWidth: Double
    var alignment: Alignment
    @ViewBuilder var content: () -> Content

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        content()
            .frame(width: fullWidth)
            .frame(width: fullWidth * min(1, max(0, progress)), alignment: alignment)
            .clipped()
            // The reveal is the only animation. Descendant frames must lay out at
            // each interpolated width instead of starting another frame animation.
            .transaction { $0.animation = nil }
    }
}
