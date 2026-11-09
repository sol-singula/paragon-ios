import SwiftUI

/// The hour, as the desktop's inbox reads it (`web/src/lib/phase.ts`, the
/// Solbuild "Sunrise" phases): warm first light in the morning, the
/// console's teal in the afternoon, violet into rose in the evening, indigo
/// at night. Same hours, same two hues. Change one, change both.
enum DayPhase: String, Equatable {
    case morning, afternoon, evening, night

    /// Night until 4, morning until noon, afternoon until 5pm, evening until
    /// 10pm, then night again.
    static func of(_ date: Date = Date(), calendar: Calendar = .current) -> DayPhase {
        let hour = calendar.component(.hour, from: date)
        if hour < 4 { return .night }
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        if hour < 22 { return .evening }
        return .night
    }

    var greeting: String {
        switch self {
        case .morning: "Good morning"
        case .afternoon: "Good afternoon"
        case .evening, .night: "Good evening"
        }
    }

    /// The big bloom in the corner and the smaller one beside it.
    var near: Color {
        switch self {
        case .morning: Color(hex: 0xF59E0B)
        case .afternoon: Color(hex: 0x14B8A6)
        case .evening: Color(hex: 0x8B5CF6)
        case .night: Color(hex: 0x6366F1)
        }
    }

    var far: Color {
        switch self {
        case .morning: Color(hex: 0xFB7185)
        case .afternoon: Color(hex: 0x22D3EE)
        case .evening: Color(hex: 0xF43F5E)
        case .night: Color(hex: 0x0EA5E9)
        }
    }

    /// Peak alphas: the desktop's dark values (0x38 / 0x22 for a morning)
    /// about 1.5x, because a phone's screen is small and the desktop's were
    /// barely there (the Setter app found the same). Still low enough that
    /// muted text keeps its contrast over the brightest corner.
    var nearAlpha: Double {
        switch self {
        case .morning: 0x54 / 255
        case .afternoon: 0x5A / 255
        case .evening: 0x56 / 255
        case .night: 0x42 / 255
        }
    }

    var farAlpha: Double {
        switch self {
        case .morning: 0x33 / 255
        case .afternoon: 0x38 / 255
        case .evening: 0x30 / 255
        case .night: 0x26 / 255
        }
    }
}

/// A radial that dies out instead of ending (`bloom()` on the desktop): the
/// same hue at a falling alpha, so the tail never passes through grey.
private func bloom(_ hue: Color, _ peak: Double) -> [Gradient.Stop] {
    let ramp: [(alpha: Double, at: CGFloat)] = [(1, 0), (0.72, 0.18), (0.42, 0.36), (0.18, 0.56), (0.05, 0.74), (0, 0.92)]
    return ramp.map { Gradient.Stop(color: hue.opacity(peak * $0.alpha), location: $0.at) }
}

/// The canvas with the hour's light at the top (founder, 2026-11-09: "our
/// morning afternoon evening etc colors on the inbox on mobile to give a
/// little more depth").
///
/// Still on purpose: no repeating animation and no blur, which is what made
/// the Setter app slow. The phase is re-read every two minutes; a change
/// crossfades once over two seconds, then nothing redraws.
struct DayGlow: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 120)) { context in
            let phase = DayPhase.of(context.date)
            ZStack {
                Theme.bg
                PhaseBloom(phase: phase)
                    .id(phase)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 2), value: phase)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PhaseBloom: View {
    let phase: DayPhase

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = min(geo.size.height * 0.55, 480)
            ZStack(alignment: .topLeading) {
                EllipticalGradient(stops: bloom(phase.near, phase.nearAlpha),
                                   center: UnitPoint(x: 0.02, y: -0.08), endRadiusFraction: 1)
                    .frame(width: w * 1.3, height: h * 1.3)
                EllipticalGradient(stops: bloom(phase.far, phase.farAlpha),
                                   center: UnitPoint(x: 0.22, y: 0.06), endRadiusFraction: 0.8)
                    .frame(width: w * 0.8, height: h)
                    .opacity(0.85)
            }
            .frame(width: w, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        // One flattened layer: list scrolling never re-renders the gradients.
        .drawingGroup()
    }
}

extension View {
    /// The canvas with the hour's light behind a main tab's list. Rows over
    /// it use a clear row background.
    func dayGlow() -> some View {
        background(DayGlow())
    }
}
