import AppKit
import SwiftUI

// MARK: - Haptics

/// Trackpad feedback for the theme editor's controls. Felt only on a Force
/// Touch trackpad; elsewhere a no-op.
enum Haptics {
    /// A detent: a dial or slider passing a step.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// A choice landing: a swatch, a mode, a space.
    static func select() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

// MARK: - Frame tint

/// What the space (or the page in front) paints over the window frame.
struct FrameTint: Equatable {
    var colors: [Color]
    var opacity: Double
    var grain: Double
}

extension LeanStore {
    /// The page's own colour when "Take the site's color" is on and it declares
    /// one, else the space's theme. Nil leaves the frame plain.
    var frameTint: FrameTint? {
        guard tabLayout == .sidebar, !glassActive else { return nil }
        let strength = isDarkMode ? 0.55 : 0.4
        let theme = currentSpace.theme
        if themedTabBar, let siteColor = selectedTab?.themeColor {
            return FrameTint(colors: [Color(nsColor: siteColor)], opacity: 0.6 * strength, grain: theme.grain)
        }
        guard theme.isTinted else { return nil }
        return FrameTint(colors: theme.colors, opacity: theme.intensity * strength, grain: theme.grain)
    }
}

/// The window frame's ground: the theme's frame colour, the tint over it
/// running top to bottom, and grain over both. The gradient is vertical so
/// the sidebar and the margin around the page, painted apart, line up.
struct FrameBackground: View {
    @ObservedObject var store: LeanStore

    var body: some View {
        ZStack {
            store.frameBackground
            if let tint = store.frameTint {
                LinearGradient(colors: Self.stops(tint.colors), startPoint: .top, endPoint: .bottom)
                    .opacity(tint.opacity)
                if tint.grain > 0 {
                    GrainTexture.image
                        .resizable(resizingMode: .tile)
                        .opacity(tint.grain * 0.18)
                        .blendMode(store.isDarkMode ? .plusLighter : .multiply)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.frameTint)
        .allowsHitTesting(false)
    }

    /// Each colour in turn, the last fading out toward the bottom.
    private static func stops(_ colors: [Color]) -> [Color] {
        guard let last = colors.last else { return [] }
        return colors + [last.opacity(0.35)]
    }
}

/// A small tile of random grey noise, made once.
private enum GrainTexture {
    static let image: Image = {
        let size = 96
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var generator = SystemRandomNumberGenerator()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8.random(in: 0...255, using: &generator)
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = 255
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        guard let provider,
              let cgImage = CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return Image(nsImage: NSImage()) }
        return Image(decorative: cgImage, scale: 2)
    }()
}

// MARK: - Editor

/// The space's look: light or dark, colours on a pad, swatches, how strong the
/// tint is and how much grain it carries, and whether pages may tint the window.
struct SpaceThemeEditor: View {
    @ObservedObject var store: LeanStore
    @State private var swatchPage = 0

    private static let swatchesPerPage = 8

    private var theme: SpaceTheme { store.currentSpace.theme }

    private func update(_ change: (inout SpaceTheme) -> Void) {
        var next = theme
        change(&next)
        store.setTheme(next, forSpace: store.selectedSpaceID)
    }

    private var ink: Color { Color.white }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                modePicker
                    .padding(.top, 10)
                ColorPad(
                    points: Binding(get: { theme.points }, set: { points in update { $0.points = points } })
                )
                .frame(height: 170)
                padActions
                    .padding(.bottom, 8)
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            swatchRow

            HStack(spacing: 14) {
                WaveSlider(
                    value: Binding(get: { theme.intensity }, set: { value in update { $0.intensity = value } }),
                    colors: theme.points.isEmpty ? [Color.white.opacity(0.6)] : theme.colors
                )
                GrainDial(value: Binding(get: { theme.grain }, set: { value in update { $0.grain = value } }))
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Take the site's color")
                        .font(store.headingFont(size: 12.5))
                        .foregroundColor(ink)
                    Text("Pages that have one tint the window.")
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(ink.opacity(0.55))
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { store.themedTabBar }, set: { on in
                    Haptics.select()
                    store.themedTabBar = on
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        )
        .environment(\.colorScheme, .dark)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { store.spaceThemeEditorFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in store.spaceThemeEditorFrame = frame }
            }
        )
        .onDisappear { store.spaceThemeEditorFrame = .zero }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            modeButton(.system, icon: .sparkle, help: "Match the system")
            modeButton(.light, icon: .sun, help: "Light")
            modeButton(.dark, icon: .moon, help: "Dark")
        }
        .padding(2)
    }

    private func modeButton(_ mode: AppTheme, icon: LeanIcon, help: String) -> some View {
        let selected = store.theme == mode
        return Button {
            guard store.theme != mode else { return }
            Haptics.select()
            withAnimation(.easeInOut(duration: 0.2)) { store.theme = mode }
        } label: {
            icon.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)
                .foregroundColor(selected ? ink : ink.opacity(0.5))
                .frame(width: 30, height: 26)
                .background(selected ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.hitArea)
        .help(help)
    }

    private var padActions: some View {
        HStack(spacing: 18) {
            padAction(.minus, help: "Remove a color", enabled: !theme.points.isEmpty) {
                update { _ = $0.points.popLast() }
            }
            padAction(.plus, help: "Add a color", enabled: theme.points.count < SpaceTheme.maxColors) {
                update { theme in
                    let anchor = theme.points.last ?? SpaceTheme.PadPoint(x: 0.7, y: 0.3)
                    let x = (anchor.x + 0.18).truncatingRemainder(dividingBy: 1)
                    theme.points.append(SpaceTheme.PadPoint(x: x, y: min(1, anchor.y + 0.2)))
                }
            }
            padAction(.arrowsCounterClockwise, help: "Shuffle the colors", enabled: !theme.points.isEmpty) {
                update { theme in
                    theme.points = theme.points.map { _ in
                        SpaceTheme.PadPoint(x: .random(in: 0...1), y: .random(in: 0.05...0.75))
                    }
                }
            }
        }
    }

    private func padAction(_ icon: LeanIcon, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            icon.bold
                .aspectRatio(contentMode: .fit)
                .frame(width: 11, height: 11)
                .foregroundColor(ink.opacity(enabled ? 0.7 : 0.25))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.hitArea)
        .disabled(!enabled)
        .help(help)
    }

    private var swatchRow: some View {
        let pages = (SpaceTheme.swatches.count + Self.swatchesPerPage - 1) / Self.swatchesPerPage
        let start = swatchPage * Self.swatchesPerPage
        let visible = SpaceTheme.swatches[start..<min(start + Self.swatchesPerPage, SpaceTheme.swatches.count)]
        return HStack(spacing: 0) {
            pageButton(.caretLeft, enabled: swatchPage > 0) { swatchPage -= 1 }
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, swatch in
                    let selected = theme.points.first == swatch
                    Button {
                        Haptics.select()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            update { $0.points = [swatch] }
                        }
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-3))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.hitArea)
                }
            }
            .id(swatchPage)
            .transition(.opacity)
            Spacer(minLength: 0)
            pageButton(.caretRight, enabled: swatchPage < pages - 1) { swatchPage += 1 }
        }
        .animation(.easeInOut(duration: 0.18), value: swatchPage)
    }

    private func pageButton(_ icon: LeanIcon, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            icon.bold
                .aspectRatio(contentMode: .fit)
                .frame(width: 9, height: 9)
                .foregroundColor(ink.opacity(enabled ? 0.6 : 0.2))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.hitArea)
        .disabled(!enabled)
    }
}

// MARK: - Colour pad

/// Colours as knobs on a field: across is the hue, down goes from vivid to
/// soft. Drag a knob, or click the field to send the first knob there. A
/// faint grid of dots marks the detents a drag ticks through.
private struct ColorPad: View {
    @Binding var points: [SpaceTheme.PadPoint]
    @State private var lastDetent: Int?

    private static let columns = 16
    private static let rows = 8
    private static let inset: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let field = CGRect(origin: .zero, size: geo.size).insetBy(dx: Self.inset, dy: Self.inset)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for column in 0...Self.columns {
                        for row in 0...Self.rows {
                            let x = field.minX + field.width * CGFloat(column) / CGFloat(Self.columns)
                            let y = field.minY + field.height * CGFloat(row) / CGFloat(Self.rows)
                            context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.07)))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    let point = Self.point(at: location, in: field)
                    Haptics.select()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        if points.isEmpty { points = [point] } else { points[0] = point }
                    }
                }

                ForEach(Array(points.enumerated()).reversed(), id: \.offset) { index, point in
                    knob(index: index, point: point, field: field)
                }
            }
            .coordinateSpace(name: "colorPad")
        }
    }

    private func knob(index: Int, point: SpaceTheme.PadPoint, field: CGRect) -> some View {
        let isPrimary = index == 0
        let diameter: CGFloat = isPrimary ? 30 : 20
        return Circle()
            .fill(point.color)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(Color.white, lineWidth: isPrimary ? 3 : 2.5))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .position(
                x: field.minX + field.width * point.x,
                y: field.minY + field.height * point.y
            )
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("colorPad"))
                    .onChanged { drag in
                        let next = Self.point(at: drag.location, in: field)
                        let detent = Self.detent(of: next)
                        if detent != lastDetent {
                            if lastDetent != nil { Haptics.tick() }
                            lastDetent = detent
                        }
                        guard points.indices.contains(index) else { return }
                        points[index] = next
                    }
                    .onEnded { _ in lastDetent = nil }
            )
    }

    private static func point(at location: CGPoint, in field: CGRect) -> SpaceTheme.PadPoint {
        SpaceTheme.PadPoint(
            x: min(1, max(0, (location.x - field.minX) / field.width)),
            y: min(1, max(0, (location.y - field.minY) / field.height))
        )
    }

    private static func detent(of point: SpaceTheme.PadPoint) -> Int {
        Int((point.x * Double(columns)).rounded()) + Int((point.y * Double(rows)).rounded()) * (columns + 1)
    }
}

// MARK: - Wave slider

/// Tint strength: a squiggle in the theme's colours up to the thumb, a grey
/// one after it. Ticks every tenth.
private struct WaveSlider: View {
    @Binding var value: Double
    let colors: [Color]
    @State private var lastStep: Int?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbX = 14 + (width - 28) * value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Wave()
                    .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .padding(.horizontal, 12)
                Wave()
                    .stroke(
                        LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .padding(.horizontal, 12)
                    .mask(alignment: .leading) { Rectangle().frame(width: thumbX) }
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 7, height: 26)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: thumbX - 3.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = min(1, max(0, (drag.location.x - 14) / (width - 28)))
                        let step = Int((next * 10).rounded())
                        if step != lastStep {
                            if lastStep != nil { Haptics.tick() }
                            lastStep = step
                        }
                        value = next
                    }
                    .onEnded { _ in lastStep = nil }
            )
        }
        .frame(height: 36)
        .help("Tint strength")
    }

    private struct Wave: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let midY = rect.midY
            let amplitude = rect.height * 0.12
            let wavelength: CGFloat = 16
            path.move(to: CGPoint(x: rect.minX, y: midY))
            var x = rect.minX
            while x <= rect.maxX {
                path.addLine(to: CGPoint(x: x, y: midY + sin((x - rect.minX) / wavelength * 2 * .pi) * amplitude))
                x += 1
            }
            return path
        }
    }
}

// MARK: - Grain dial

/// Grain amount as a knob: drag up or right to turn it up, with a detent
/// at every one of the dots around it.
private struct GrainDial: View {
    @Binding var value: Double
    @State private var dragStart: Double?
    @State private var lastStep: Int?

    private static let steps = 20
    /// The knob turns through 270°, from bottom-left to bottom-right.
    private static let sweep = 270.0
    private static let startAngle = 135.0

    var body: some View {
        ZStack {
            ForEach(0...Self.steps, id: \.self) { step in
                let fraction = Double(step) / Double(Self.steps)
                Circle()
                    .fill(Color.white.opacity(fraction <= value + 0.001 ? 0.75 : 0.2))
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: 25)
                    .rotationEffect(.degrees(Self.startAngle + Self.sweep * fraction))
            }
            Circle()
                .fill(
                    RadialGradient(colors: [Color(white: 0.32), Color(white: 0.16)], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 26)
                )
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .overlay(
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 7, height: 2.5)
                        .offset(x: 12)
                        .rotationEffect(.degrees(Self.startAngle + Self.sweep * value))
                )
        }
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = dragStart ?? value
                    if dragStart == nil { dragStart = value }
                    let delta = (drag.translation.width - drag.translation.height) / 160
                    let next = min(1, max(0, start + delta))
                    let step = Int((next * Double(Self.steps)).rounded())
                    if step != lastStep {
                        if lastStep != nil { Haptics.tick() }
                        lastStep = step
                    }
                    value = next
                }
                .onEnded { _ in
                    dragStart = nil
                    lastStep = nil
                }
        )
        .help("Grain")
    }
}
