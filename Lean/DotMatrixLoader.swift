import SwiftUI

/// The app-wide loading indicator. Every spinner in the app is a
/// `DotMatrixLoader` (the name predates the choice); which drawing it shows
/// is Settings › Tabs › Loading Indicator, read live from `LoaderStyle`.
struct DotMatrixLoader: View {
    let color: Color
    var size: CGFloat = 14
    @AppStorage(LoaderStyle.storageKey) private var styleRaw = LoaderStyle.defaultStyle.rawValue

    var body: some View {
        LoaderView(style: LoaderStyle(rawValue: styleRaw) ?? .defaultStyle, color: color, size: size)
    }
}

enum LoaderStyle: String, CaseIterable, Identifiable {
    case ring, dotMatrix, pulse, bars, orbit, ripple

    static let storageKey = "loaderStyle"
    static let defaultStyle = LoaderStyle.ring

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: return "Ring"
        case .dotMatrix: return "Dot Matrix"
        case .pulse: return "Pulse"
        case .bars: return "Bars"
        case .orbit: return "Orbit"
        case .ripple: return "Ripple"
        }
    }
}

/// One loader drawing, for a given style. Also what the settings previews show.
struct LoaderView: View {
    let style: LoaderStyle
    let color: Color
    var size: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch style {
        case .dotMatrix:
            DotMatrixGrid(color: color, size: size)
        case .ring, .pulse, .bars, .orbit, .ripple:
            // Under Reduce Motion nothing runs: a fixed frame of the drawing.
            if reduceMotion {
                frame(at: 0.35)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    frame(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    @ViewBuilder
    private func frame(at t: TimeInterval) -> some View {
        // Drawn a little smaller than the slot it is given, so it sits as
        // lightly as the dots did.
        let d = size * 0.78
        switch style {
        case .ring:
            Circle()
                .trim(from: 0.0, to: 0.72)
                .stroke(color, style: StrokeStyle(lineWidth: max(1.5, d * 0.13), lineCap: .round))
                .rotationEffect(.degrees((t * 420).truncatingRemainder(dividingBy: 360)))
                .padding(max(1.5, d * 0.13) / 2)
                .frame(width: d, height: d)
        case .pulse:
            HStack(spacing: d * 0.14) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = 0.5 + 0.5 * sin(t * 6.5 - Double(i) * 0.9)
                    Circle()
                        .fill(color)
                        .frame(width: d * 0.24, height: d * 0.24)
                        .scaleEffect(0.6 + 0.5 * wave)
                        .opacity(0.35 + 0.65 * wave)
                }
            }
            .frame(width: d, height: d)
        case .bars:
            HStack(alignment: .center, spacing: d * 0.1) {
                ForEach(0..<4, id: \.self) { i in
                    let wave = 0.5 + 0.5 * sin(t * 7.0 - Double(i) * 0.8)
                    Capsule()
                        .fill(color)
                        .frame(width: max(1.6, d * 0.15), height: d * (0.3 + 0.7 * wave))
                }
            }
            .frame(width: d, height: d)
        case .orbit:
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: max(1, d * 0.07))
                ForEach(0..<6, id: \.self) { i in
                    let angle = t * 5.0 - Double(i) * 0.28
                    Circle()
                        .fill(color)
                        .frame(width: d * 0.2, height: d * 0.2)
                        .opacity(1.0 - Double(i) * 0.17)
                        .offset(x: cos(angle) * d * 0.4, y: sin(angle) * d * 0.4)
                }
            }
            .frame(width: d, height: d)
        case .ripple:
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let phase = (t * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1.0)
                    Circle()
                        .stroke(color, lineWidth: max(1.2, d * 0.09))
                        .scaleEffect(0.15 + 0.85 * phase)
                        .opacity(1.0 - phase)
                }
            }
            .frame(width: d, height: d)
        case .dotMatrix:
            EmptyView()
        }
    }
}

/// The original nine-dot grid.
private struct DotMatrixGrid: View {
    let color: Color
    var size: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dotSize: CGFloat {
        max(1.8, size * 0.17)
    }

    private var spacing: CGFloat {
        max(1.5, size * 0.15)
    }

    var body: some View {
        // One 8fps TimelineView drives all 9 dots. Previously each dot ran
        // its own repeatForever animation (9 concurrent CoreAnimation loops
        // per loading tab x N loading tabs). Under Reduce Motion the dots
        // are fixed, so no timeline runs at all.
        if reduceMotion {
            dots(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
                dots(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    @ViewBuilder
    private func dots(at t: TimeInterval) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { column in
                        let idx = Double(row * 3 + column)
                        let phase = reduceMotion ? 0.9 : 0.20 + 0.70 * (0.5 + 0.5 * sin(t * 7.0 - idx * 0.7))
                        Circle()
                            .fill(color)
                            .frame(width: dotSize, height: dotSize)
                            .opacity(phase)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}
