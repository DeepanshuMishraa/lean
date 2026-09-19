import SwiftUI

struct DotMatrixLoader: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { column in
                        Circle()
                            .fill(color)
                            .frame(width: 2.5, height: 2.5)
                            .opacity(isAnimating ? 0.8 : 0.2)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(row * 3 + column) * 0.05),
                                value: isAnimating
                            )
                    }
                }
            }
        }
        .frame(width: 20, height: 20)
        .onAppear { isAnimating = true }
    }
}
