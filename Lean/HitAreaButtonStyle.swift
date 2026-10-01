import SwiftUI

/// Plain button style whose entire label bounds are clickable.
/// `.plain` hit-tests only opaque pixels, so clicks on padding, transparent
/// gaps or a `Spacer` fall through; this style makes the full frame respond.
struct HitAreaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}

/// The tab close button: full hit area, and a small press that gives way
/// instantly and springs back (press in fast, release a touch slower).
struct TabCloseButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == HitAreaButtonStyle {
    static var hitArea: HitAreaButtonStyle { HitAreaButtonStyle() }
}
