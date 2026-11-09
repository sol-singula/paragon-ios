import SwiftUI

/// Atlas's mark: the violet ring the desktop puts beside everything Atlas
/// wrote, suggested or heard.
struct AtlasRing: View {
    var size: CGFloat = 16
    var spinning = false
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .strokeBorder(AngularGradient(colors: Theme.atlasGradient, center: .center), lineWidth: max(1.5, size * 0.16))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard spinning else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { angle = 360 }
            }
            .accessibilityLabel("Atlas")
    }
}
