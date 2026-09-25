import SwiftUI

struct DotMatrixLoader: View {
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
        // per loading tab x N loading tabs).
        TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
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
}
