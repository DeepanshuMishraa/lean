import SwiftUI
import AppKit

// MARK: - Settings Group Container
/// A continuous, quiet surface that groups related settings with subtle hairline borders and dividers.
struct SettingsGroup<Content: View>: View {
    let isDark: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.02),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.75)
        )
    }
}

// MARK: - Settings Row Divider
struct SettingsRowDivider: View {
    let isDark: Bool
    var inset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
            .frame(height: 0.75)
            .padding(.leading, inset)
    }
}

// MARK: - Section Header
struct SettingsHeaderLabel: View {
    let title: String
    let subtitle: String?
    let uiFont: LeanFont
    let isDark: Bool

    init(_ title: String, subtitle: String? = nil, uiFont: LeanFont, isDark: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.uiFont = uiFont
        self.isDark = isDark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(uiFont.font(size: 11, weight: .semibold))
                .foregroundColor(isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                .textCase(.uppercase)
                .tracking(0.8)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(uiFont.font(size: 12))
                    .foregroundColor(isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.50))
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Dropdown Menu State & Event Coordinator
@MainActor
final class DropdownMenuState: ObservableObject {
    @Published var activeId: String? = nil {
        didSet {
            if activeId != nil {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    private var eventMonitor: Any?

    private func startMonitoring() {
        stopMonitoring()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self = self, self.activeId != nil else { return event }

            if event.type == .keyDown && event.keyCode == 53 { // Escape key
                self.dismiss()
                return nil
            }

            if event.type == .scrollWheel && (abs(event.scrollingDeltaX) > 1.5 || abs(event.scrollingDeltaY) > 1.5) {
                self.dismiss()
                return event
            }

            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func toggle(_ id: String) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            if activeId == id {
                activeId = nil
            } else {
                activeId = id
            }
        }
    }

    func dismiss() {
        withAnimation(.spring(response: 0.20, dampingFraction: 0.82)) {
            activeId = nil
        }
    }

    func isActive(_ id: String) -> Bool {
        activeId == id
    }
}

// MARK: - Search Engine Badge View
struct SearchEngineBadgeView: View {
    let engine: SearchEngine
    let isDark: Bool
    var size: CGFloat = 16

    @State private var cachedImage: NSImage?

    var body: some View {
        Group {
            if let cachedImage {
                Image(nsImage: cachedImage)
                    .resizable()
                    .scaledToFit()
            } else {
                engineFallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        .onAppear {
            if let img = FaviconService.shared.cachedFavicon(for: engine.searchURL) {
                cachedImage = img
            } else {
                FaviconService.shared.loadFavicon(for: engine.searchURL) { loaded in
                    if let loaded {
                        cachedImage = loaded
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var engineFallbackIcon: some View {
        switch engine {
        case .google:
            ZStack {
                Circle().fill(Color(red: 66/255, green: 133/255, blue: 244/255))
                Text("G")
                    .font(.system(size: size * 0.65, weight: .bold))
                    .foregroundColor(.white)
            }
        case .duckDuckGo:
            ZStack {
                Circle().fill(Color(red: 222/255, green: 88/255, blue: 51/255))
                Image(systemName: "shield.fill")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundColor(.white)
            }
        case .bing:
            ZStack {
                Circle().fill(Color(red: 0/255, green: 131/255, blue: 143/255))
                Text("b")
                    .font(.system(size: size * 0.65, weight: .bold))
                    .foregroundColor(.white)
            }
        case .brave:
            ZStack {
                Circle().fill(Color(red: 251/255, green: 84/255, blue: 43/255))
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundColor(.white)
            }
        case .ecosia:
            ZStack {
                Circle().fill(Color(red: 0/255, green: 138/255, blue: 94/255))
                Image(systemName: "leaf.fill")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundColor(.white)
            }
        case .yahoo:
            ZStack {
                Circle().fill(Color(red: 114/255, green: 14/255, blue: 206/255))
                Text("Y!")
                    .font(.system(size: size * 0.52, weight: .black))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Bespoke Dropdown Trigger Button
struct CustomDropdownButton<Leading: View>: View {
    let text: String
    let font: Font
    let isDark: Bool
    let isPresented: Bool
    var leading: Leading? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var buttonBackground: Color {
        if isPresented {
            return isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)
        } else if isHovered {
            return isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05)
        } else {
            return isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
        }
    }

    private var buttonBorder: Color {
        if isPresented {
            return isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        } else {
            return isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let leading {
                    leading
                }

                Text(text)
                    .font(font)
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))

                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.45))
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                buttonBackground,
                in: RoundedRectangle(cornerRadius: 6.5, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .stroke(buttonBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Bespoke Floating Dropdown Card
struct CustomDropdownCard<Content: View>: View {
    let isDark: Bool
    var width: CGFloat = 210
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 1.5) {
            content()
        }
        .padding(4)
        .frame(width: width)
        .background(
            (isDark
                ? Color(red: 22/255, green: 22/255, blue: 25/255)
                : Color(white: 0.995)
            ).opacity(0.97)
        )
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(
            color: Color.black.opacity(isDark ? 0.45 : 0.12),
            radius: 16,
            x: 0,
            y: 8
        )
        .shadow(
            color: Color.black.opacity(isDark ? 0.20 : 0.04),
            radius: 2,
            x: 0,
            y: 1
        )
    }
}

// MARK: - Bespoke Dropdown Item Row
struct CustomDropdownItemRow<Leading: View>: View {
    let title: String
    let font: Font
    let isSelected: Bool
    let isDark: Bool
    var leading: Leading? = nil
    let onSelect: () -> Void

    @State private var isHovered = false

    private var textColor: Color {
        if isSelected {
            return isDark ? Color.white : Color.black
        }
        return isDark ? Color(white: 0.88) : Color(white: 0.18)
    }

    private var rowBackground: Color {
        if isHovered {
            return isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.05)
        } else if isSelected {
            return isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
        }
        return Color.clear
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                if let leading {
                    leading
                }

                Text(title)
                    .font(font)
                    .foregroundColor(textColor)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(isDark ? Color.white : Color.black)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(
                rowBackground,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Search Engine Picker Row (Custom Dropdown)
struct SearchEnginePickerRow: View {
    @Binding var selection: SearchEngine
    let uiFont: LeanFont
    let isDark: Bool

    @EnvironmentObject private var dropdownState: DropdownMenuState
    private let pickerId = "searchEnginePicker"

    private var isPresented: Bool {
        dropdownState.isActive(pickerId)
    }

    @State private var isRowHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text("Default search engine")
                    .font(uiFont.font(size: 13, weight: .medium))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))

                Text("Queries entered into the omnibar are directed to this engine")
                    .font(uiFont.font(size: 11.5))
                    .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.48))
            }

            Spacer(minLength: 16)

            CustomDropdownButton(
                text: selection.name,
                font: uiFont.font(size: 12.5, weight: .medium),
                isDark: isDark,
                isPresented: isPresented,
                leading: SearchEngineBadgeView(engine: selection, isDark: isDark, size: 15)
            ) {
                dropdownState.toggle(pickerId)
            }
            .overlay(alignment: .topTrailing) {
                if isPresented {
                    CustomDropdownCard(isDark: isDark, width: 205) {
                        ForEach(SearchEngine.allCases) { engine in
                            let isChosen = selection == engine
                            CustomDropdownItemRow(
                                title: engine.name,
                                font: uiFont.font(size: 12.5, weight: isChosen ? .semibold : .regular),
                                isSelected: isChosen,
                                isDark: isDark,
                                leading: SearchEngineBadgeView(engine: engine, isDark: isDark, size: 15)
                            ) {
                                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                                    selection = engine
                                }
                                dropdownState.dismiss()
                            }
                        }
                    }
                    .offset(y: 33)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity)
                    ))
                    .zIndex(200)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(
            isRowHovered
                ? (isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015))
                : Color.clear
        )
        .onHover { isRowHovered = $0 }
        .zIndex(isPresented ? 100 : 1)
    }
}

// MARK: - Font Picker Row (Custom Dropdown)
struct FontPickerRow: View {
    let title: String
    let subtitle: String?
    @Binding var selection: LeanFont
    let uiFont: LeanFont
    let isDark: Bool
    let pickerId: String

    @EnvironmentObject private var dropdownState: DropdownMenuState

    private var isPresented: Bool {
        dropdownState.isActive(pickerId)
    }

    @State private var isRowHovered = false

    init(
        title: String,
        subtitle: String? = nil,
        selection: Binding<LeanFont>,
        uiFont: LeanFont,
        isDark: Bool,
        pickerId: String = UUID().uuidString
    ) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.uiFont = uiFont
        self.isDark = isDark
        self.pickerId = pickerId
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(uiFont.font(size: 13, weight: .medium))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(uiFont.font(size: 11.5))
                        .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.48))
                }
            }

            Spacer(minLength: 16)

            CustomDropdownButton(
                text: selection.rawValue,
                font: selection.font(size: 12.5, weight: .medium),
                isDark: isDark,
                isPresented: isPresented,
                leading: nil as EmptyView?
            ) {
                dropdownState.toggle(pickerId)
            }
            .overlay(alignment: .topTrailing) {
                if isPresented {
                    CustomDropdownCard(isDark: isDark, width: 215) {
                        ForEach(LeanFont.allCases) { fontChoice in
                            let isChosen = selection == fontChoice
                            CustomDropdownItemRow(
                                title: fontChoice.rawValue,
                                font: fontChoice.font(size: 13, weight: isChosen ? .semibold : .regular),
                                isSelected: isChosen,
                                isDark: isDark,
                                leading: nil as EmptyView?
                            ) {
                                withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                                    selection = fontChoice
                                }
                                dropdownState.dismiss()
                            }
                        }
                    }
                    .offset(y: 33)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity)
                    ))
                    .zIndex(200)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(
            isRowHovered
                ? (isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015))
                : Color.clear
        )
        .onHover { isRowHovered = $0 }
        .zIndex(isPresented ? 100 : 1)
    }
}

// MARK: - Custom Minimal Segmented Picker with Fluid Geometry Slider
struct SegmentOption: Identifiable {
    let id: String
    let label: String
    let icon: String?

    init(id: String, label: String, icon: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
    }
}

struct CustomSegmentedPicker: View {
    let options: [SegmentOption]
    let selectedId: String
    let isDark: Bool
    let uiFont: LeanFont
    let onSelect: (String) -> Void

    @Namespace private var segmentAnimation
    @State private var hoveredId: String? = nil

    private func textColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return isDark ? Color.white : Color(white: 0.08)
        } else if isHovered {
            return isDark ? Color.white.opacity(0.80) : Color.black.opacity(0.75)
        } else {
            return isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.42)
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                let isSelected = opt.id == selectedId
                let isHovered = opt.id == hoveredId

                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        onSelect(opt.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = opt.icon {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        }
                        Text(opt.label)
                            .font(uiFont.font(size: 12, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(textColor(isSelected: isSelected, isHovered: isHovered))
                    .frame(maxWidth: .infinity)
                    .frame(height: 27)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    isDark
                                        ? Color(white: 0.17)
                                        : Color.white
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            isDark
                                                ? Color.white.opacity(0.12)
                                                : Color.black.opacity(0.06),
                                            lineWidth: 0.5
                                        )
                                )
                                .shadow(
                                    color: isDark ? Color.black.opacity(0.32) : Color.black.opacity(0.06),
                                    radius: isDark ? 2 : 2.5,
                                    y: 1
                                )
                                .matchedGeometryEffect(id: "activeSegment", in: segmentAnimation)
                        } else if isHovered {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { h in
                    hoveredId = h ? opt.id : (hoveredId == opt.id ? nil : hoveredId)
                }
            }
        }
        .padding(2.5)
        .frame(height: 32)
        .background(
            isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// MARK: - Custom Minimal Switch / Toggle
struct CustomToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    let isDark: Bool
    let uiFont: LeanFont

    @State private var isHovered = false

    init(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>,
        isDark: Bool,
        uiFont: LeanFont
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.isDark = isDark
        self.uiFont = uiFont
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(uiFont.font(size: 13, weight: .medium))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(uiFont.font(size: 11.5))
                        .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.48))
                        .lineSpacing(1.5)
                }
            }

            Spacer(minLength: 16)

            // Tactile Minimal Precision Switch
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? (isDark ? Color.white : Color(white: 0.10))
                            : (isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                isOn
                                    ? Color.clear
                                    : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                                lineWidth: 0.5
                            )
                    )
                    .frame(width: 34, height: 19)

                Circle()
                    .fill(
                        isOn
                            ? (isDark ? Color(white: 0.08) : Color.white)
                            : (isDark ? Color.white.opacity(0.85) : Color.white)
                    )
                    .frame(width: 13, height: 13)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, y: 0.5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(
            isHovered
                ? (isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015))
                : Color.clear
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        }
    }
}

// MARK: - Frame Width Picker Row
struct FrameWidthPickerRow: View {
    @ObservedObject var store: LeanStore
    let isDark: Bool
    let uiFont: LeanFont

    @Namespace private var frameWidthAnimation
    @State private var hoveredWidth: CGFloat? = nil

    private let widths: [(label: String, width: CGFloat, previewLine: CGFloat)] = [
        ("Thin", 5.0, 1.5),
        ("Normal", 8.0, 3.0),
        ("Thick", 12.0, 5.0)
    ]

    private func textColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return isDark ? Color.white : Color(white: 0.08)
        } else if isHovered {
            return isDark ? Color.white.opacity(0.80) : Color.black.opacity(0.75)
        } else {
            return isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.42)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text("Border thickness")
                    .font(uiFont.font(size: 13, weight: .medium))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))
                Text("Outer margin width around the web page canvas")
                    .font(uiFont.font(size: 11.5))
                    .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.48))
            }

            Spacer(minLength: 16)

            HStack(spacing: 2) {
                ForEach(widths, id: \.width) { item in
                    let isSelected = store.windowBorderWidth == item.width
                    let isHovered = hoveredWidth == item.width

                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                            store.windowBorderWidth = item.width
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Capsule()
                                .fill(isSelected ? (isDark ? Color.white : Color(white: 0.10)) : (isDark ? Color.white.opacity(0.4) : Color.black.opacity(0.35)))
                                .frame(width: 10, height: item.previewLine)

                            Text(item.label)
                                .font(uiFont.font(size: 11.5, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundColor(textColor(isSelected: isSelected, isHovered: isHovered))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .fill(isDark ? Color(white: 0.17) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                            .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 0.5)
                                    )
                                    .shadow(
                                        color: isDark ? Color.black.opacity(0.3) : Color.black.opacity(0.06),
                                        radius: 2,
                                        y: 1
                                    )
                                    .matchedGeometryEffect(id: "activeFrameWidth", in: frameWidthAnimation)
                            } else if isHovered {
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        hoveredWidth = h ? item.width : (hoveredWidth == item.width ? nil : hoveredWidth)
                    }
                }
            }
            .padding(2.5)
            .background(
                isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 7.5, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .stroke(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
