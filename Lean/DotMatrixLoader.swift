import SwiftUI

struct DotMatrixLoader: View {
    let color: Color
    var size: CGFloat = 14
    @State private var isAnimating = false

    private var dotSize: CGFloat {
        max(1.8, size * 0.17)
    }

    private var spacing: CGFloat {
        max(1.5, size * 0.15)
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { column in
                        Circle()
                            .fill(color)
                            .frame(width: dotSize, height: dotSize)
                            .opacity(isAnimating ? 0.90 : 0.20)
                            .animation(
                                .easeInOut(duration: 0.45)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(row * 3 + column) * 0.045),
                                value: isAnimating
                            )
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            isAnimating = false
            DispatchQueue.main.async {
                isAnimating = true
            }
        }
        .onDisappear {
            isAnimating = false
        }
    }
}
