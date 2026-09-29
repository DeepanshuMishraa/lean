import SwiftUI

/// Plain button style whose entire label bounds are clickable.
/// `.plain` hit-tests only opaque pixels, so clicks on padding, transparent
/// gaps or a `Spacer` fall through; this style makes the full frame respond.
struct HitAreaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == HitAreaButtonStyle {
    static var hitArea: HitAreaButtonStyle { HitAreaButtonStyle() }
}
