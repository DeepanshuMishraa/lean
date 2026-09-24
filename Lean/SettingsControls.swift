import AppKit
import SwiftUI

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

private struct LeanSettingsFontKey: EnvironmentKey {
    static let defaultValue = LeanFont.system
}

extension EnvironmentValues {
    var leanSettingsFont: LeanFont {
        get { self[LeanSettingsFontKey.self] }
        set { self[LeanSettingsFontKey.self] = newValue }
    }
}

struct SettingsActionButton: View {
    let title: String
    let isDark: Bool
    var prominent = false
    var destructive = false
    var isLoading = false
    let action: () -> Void

    @Environment(\.leanSettingsFont) private var uiFont
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    init(_ title: String, isDark: Bool, prominent: Bool = false, destructive: Bool = false, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDark = isDark
        self.prominent = prominent
        self.destructive = destructive
        self.isLoading = isLoading
        self.action = action
    }

    private var textColor: Color {
        if destructive { return .red }
        if prominent { return isDark ? .black : .white }
        return isDark ? Color.white.opacity(0.82) : Color.black.opacity(0.76)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading { DotMatrixLoader(color: textColor, size: 11) }
                Text(title)
                    .font(uiFont.font(size: 11.5, weight: prominent ? .medium : .regular))
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
                .background(
                    prominent ? (isDark ? Color.white : Color.black.opacity(0.82))
                        : (hovering ? (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)) : .clear),
                    in: Capsule()
                )
                .overlay {
                    if !prominent {
                        Capsule().strokeBorder(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.09), lineWidth: 0.75)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.14), value: hovering)
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
    var headingWeight: LeanFontWeight = .semibold
    var bodyWeight: LeanFontWeight = .regular

    init(
        _ title: String,
        subtitle: String? = nil,
        uiFont: LeanFont,
        isDark: Bool,
        headingWeight: LeanFontWeight = .semibold,
        bodyWeight: LeanFontWeight = .regular
    ) {
        self.title = title
        self.subtitle = subtitle
        self.uiFont = uiFont
        self.isDark = isDark
        self.headingWeight = headingWeight
        self.bodyWeight = bodyWeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(uiFont.font(size: 11, weight: headingWeight.fontWeight))
                .foregroundColor(isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.40))
                .textCase(.uppercase)
                .tracking(0.8)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(uiFont.font(size: 12, weight: bodyWeight.fontWeight))
                    .foregroundColor(isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.50))
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Dropdown Menu State
@MainActor
final class DropdownMenuState: ObservableObject {
    @Published var activeId: String?

    func toggle(_ id: String) {
        activeId = activeId == id ? nil : id
    }

    func dismiss() {
        activeId = nil
    }

    func isActive(_ id: String) -> Bool {
        activeId == id
    }

    func presentationBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { self.activeId == id },
            set: { self.activeId = $0 ? id : nil }
        )
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
                Ph.shield.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.55, height: size * 0.55)
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
                Ph.fire.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.55, height: size * 0.55)
                    .foregroundColor(.white)
            }
        case .ecosia:
            ZStack {
                Circle().fill(Color(red: 0/255, green: 138/255, blue: 94/255))
                Ph.leaf.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.55, height: size * 0.55)
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

                Ph.caretDown.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 9, height: 9)
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
                    .stroke(buttonBorder, lineWidth: 0.75)
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
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isDark
                        ? Color(red: 24/255, green: 24/255, blue: 27/255)
                        : Color.white
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.75)
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
                    Ph.check.bold
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10)
                        .foregroundColor(isDark ? Color.white : Color.black)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 29)
            .background(
                rowBackground,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
            .popover(isPresented: dropdownState.presentationBinding(for: pickerId), arrowEdge: .bottom) {
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
                            selection = engine
                            dropdownState.dismiss()
                        }
                    }
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
    var headingWeight: LeanFontWeight = .medium
    var bodyWeight: LeanFontWeight = .regular

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
        pickerId: String = UUID().uuidString,
        headingWeight: LeanFontWeight = .medium,
        bodyWeight: LeanFontWeight = .regular
    ) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.uiFont = uiFont
        self.isDark = isDark
        self.pickerId = pickerId
        self.headingWeight = headingWeight
        self.bodyWeight = bodyWeight
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(uiFont.font(size: 13, weight: headingWeight.fontWeight))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(uiFont.font(size: 11.5, weight: bodyWeight.fontWeight))
                        .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.48))
                }
            }

            Spacer(minLength: 16)

            CustomDropdownButton(
                text: selection.displayName,
                font: selection.font(size: 12.5, weight: .medium),
                isDark: isDark,
                isPresented: isPresented,
                leading: nil as EmptyView?
            ) {
                dropdownState.toggle(pickerId)
            }
            .popover(isPresented: dropdownState.presentationBinding(for: pickerId), arrowEdge: .bottom) {
                CustomDropdownCard(isDark: isDark, width: 215) {
                    ForEach(LeanFont.allCases) { fontChoice in
                        let isChosen = selection == fontChoice
                        CustomDropdownItemRow(
                            title: fontChoice.displayName,
                            font: fontChoice.font(size: 13, weight: isChosen ? .semibold : .regular),
                            isSelected: isChosen,
                            isDark: isDark,
                            leading: nil as EmptyView?
                        ) {
                            selection = fontChoice
                            dropdownState.dismiss()
                        }
                    }
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
    let icon: Ph?

    init(id: String, label: String, icon: Ph? = nil) {
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

    @State private var hoveredId: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                SegmentButton(
                    option: opt,
                    isSelected: opt.id == selectedId,
                    isHovered: opt.id == hoveredId,
                    isDark: isDark,
                    uiFont: uiFont,
                    onSelect: { onSelect(opt.id) },
                    onHover: { h in
                        hoveredId = h ? opt.id : (hoveredId == opt.id ? nil : hoveredId)
                    }
                )
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

private struct SegmentButton: View {
    let option: SegmentOption
    let isSelected: Bool
    let isHovered: Bool
    let isDark: Bool
    let uiFont: LeanFont
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    private var textColor: Color {
        if isSelected { return isDark ? Color.white : Color(white: 0.08) }
        if isHovered { return isDark ? Color.white.opacity(0.80) : Color.black.opacity(0.75) }
        return isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.42)
    }

    private var fill: Color {
        if isSelected { return isDark ? Color(white: 0.17) : Color.white }
        if isHovered { return isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025) }
        return Color.clear
    }

    private var stroke: Color? {
        guard isSelected else { return nil }
        return isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }

    private var shadow: Color {
        guard isSelected else { return Color.clear }
        return isDark ? Color.black.opacity(0.32) : Color.black.opacity(0.06)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if let icon = option.icon {
                    icon.fill
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                }
                Text(option.label)
                    .font(uiFont.font(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
                    .overlay(
                        Group {
                            if let stroke {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(stroke, lineWidth: 0.5)
                            }
                        }
                    )
                    .shadow(color: shadow, radius: 2, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
    }
}

// MARK: - Custom Minimal Switch / Toggle
struct TactileSwitch: View {
    @Binding var isOn: Bool
    let isDark: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? (isDark ? Color.white : Color(white: 0.10))
                            : (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
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
        .buttonStyle(.plain)
    }
}

struct CustomToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    let isDark: Bool
    let uiFont: LeanFont
    var headingWeight: LeanFontWeight = .medium
    var bodyWeight: LeanFontWeight = .regular

    @State private var isHovered = false

    init(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>,
        isDark: Bool,
        uiFont: LeanFont,
        headingWeight: LeanFontWeight = .medium,
        bodyWeight: LeanFontWeight = .regular
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.isDark = isDark
        self.uiFont = uiFont
        self.headingWeight = headingWeight
        self.bodyWeight = bodyWeight
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(uiFont.font(size: 13, weight: headingWeight.fontWeight))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(uiFont.font(size: 11.5, weight: bodyWeight.fontWeight))
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

struct CustomChecklistRow: View {
    let title: String
    @Binding var isOn: Bool
    let isDark: Bool
    let uiFont: LeanFont

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { isOn.toggle() }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(uiFont.font(size: 12.5, weight: isOn ? .medium : .regular))
                    .foregroundColor(isDark ? Color.white.opacity(0.88) : Color.black.opacity(0.78))
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? (isDark ? Color.white : Color.black.opacity(0.82)) : .clear)
                    .frame(width: 15, height: 15)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isOn ? .clear : (isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.20)), lineWidth: 0.8)
                    }
                    .overlay {
                        if isOn {
                            Ph.check.bold
                                .foregroundColor(isDark ? .black : .white)
                                .frame(width: 9, height: 9)
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHovered ? (isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.018)) : .clear)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
    }
}

// MARK: - Frame Width Picker Row
struct FrameWidthPickerRow: View {
    @ObservedObject var store: LeanStore
    let isDark: Bool
    let uiFont: LeanFont

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
                        store.windowBorderWidth = item.width
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
                        .background(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(
                                    isSelected
                                        ? (isDark ? Color(white: 0.17) : Color.white)
                                        : (isHovered ? (isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)) : Color.clear)
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
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

// MARK: - Bespoke Settings Slider (Scrubbable Track Control)
/// Minimal scrubbable slider reused for discrete numeric settings.
struct SettingsValueSlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let label: String
    var valueSuffix = ""
    let isDark: Bool
    let uiFont: LeanFont
    var width: CGFloat = 215
    var height: CGFloat = 30

    @State private var isDragging = false
    @State private var isHovered = false

    private var progress: CGFloat {
        CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }

    private var emptyTrackColor: Color {
        isDark ? Color(red: 63/255, green: 63/255, blue: 70/255) : Color(white: 0.88)
    }

    private var filledTrackColor: Color {
        isDark ? Color(red: 79/255, green: 79/255, blue: 84/255) : Color(white: 0.76)
    }

    private var thumbColor: Color {
        if isDragging {
            return isDark ? Color(white: 0.95) : Color(white: 0.15)
        } else if isHovered {
            return isDark ? Color(white: 0.82) : Color(white: 0.30)
        } else {
            return isDark ? Color(red: 143/255, green: 143/255, blue: 146/255) : Color(white: 0.52)
        }
    }

    private var labelColor: Color {
        isDark ? Color.white.opacity(0.60) : Color.black.opacity(0.50)
    }

    private var valueColor: Color {
        isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private func updateValue(at x: CGFloat, totalWidth: CGFloat) {
        let minThumbX: CGFloat = 16
        let maxThumbX = totalWidth - 16
        let clampedX = max(minThumbX, min(x, maxThumbX))
        let fraction = (clampedX - minThumbX) / max(maxThumbX - minThumbX, 1)
        let raw = Double(range.lowerBound) + Double(fraction) * Double(range.upperBound - range.lowerBound)
        let stepped = Int((raw / Double(step)).rounded()) * step
        let nextValue = min(range.upperBound, max(range.lowerBound, stepped))
        if nextValue != value { value = nextValue }
    }

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let totalH = geo.size.height
            let minThumbX: CGFloat = 16
            let maxThumbX = totalW - 16
            let thumbX = minThumbX + progress * (maxThumbX - minThumbX)
            let thumbW: CGFloat = 3.5
            let thumbH: CGFloat = 18

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(emptyTrackColor)

                Rectangle()
                    .fill(filledTrackColor)
                    .frame(width: max(thumbX + thumbW / 2, 0))

                RoundedRectangle(cornerRadius: 1.75, style: .continuous)
                    .fill(thumbColor)
                    .frame(width: thumbW, height: thumbH)
                    .shadow(color: Color.black.opacity(isDark ? 0.30 : 0.10), radius: isDragging ? 2.5 : 1, y: 0.5)
                    .position(x: thumbX, y: totalH / 2)

                HStack {
                    Text(label)
                        .font(uiFont.font(size: 11.5, weight: .medium))
                        .foregroundColor(labelColor)
                        .padding(.leading, 11)

                    Spacer()

                    Text("\(value)\(valueSuffix)")
                        .font(uiFont.font(size: 11.5, weight: .medium))
                        .foregroundColor(valueColor)
                        .padding(.trailing, 11)
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .stroke(
                        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                        lineWidth: 0.75
                    )
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        updateValue(at: gesture.location.x, totalWidth: totalW)
                    }
                    .onEnded { gesture in
                        updateValue(at: gesture.location.x, totalWidth: totalW)
                        isDragging = false
                    }
            )
            .help("\(value)\(valueSuffix)")
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(value)\(valueSuffix)")
            .accessibilityAdjustableAction { direction in
                let snappedValue = Int((Double(value) / Double(step)).rounded()) * step
                switch direction {
                case .increment: value = min(range.upperBound, snappedValue + step)
                case .decrement: value = max(range.lowerBound, snappedValue - step)
                @unknown default: break
                }
            }
        }
        .frame(width: width, height: height)
    }
}

struct FontWeightSlider: View {
    @Binding var weight: LeanFontWeight
    let label: String
    let isDark: Bool
    let uiFont: LeanFont
    var width: CGFloat = 215

    var body: some View {
        SettingsValueSlider(
            value: Binding(
                get: { weight.rawValue },
                set: { weight = LeanFontWeight(closestTo: Double($0)) }
            ),
            range: 100...900,
            step: 100,
            label: label,
            isDark: isDark,
            uiFont: uiFont,
            width: width
        )
    }
}

// MARK: - Font Weight Slider Row
struct FontWeightSliderRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: LeanFontWeight
    let label: String
    let uiFont: LeanFont
    let isDark: Bool
    var headingWeight: LeanFontWeight = .medium
    var bodyWeight: LeanFontWeight = .regular

    var body: some View {
        SettingsSliderRow(
            title: title,
            subtitle: subtitle,
            uiFont: uiFont,
            isDark: isDark,
            headingWeight: headingWeight,
            bodyWeight: bodyWeight
        ) {
            FontWeightSlider(
                weight: $value,
                label: label,
                isDark: isDark,
                uiFont: uiFont,
                width: 215
            )
        }
    }
}

struct SettingsSliderRow<Control: View>: View {
    let title: String
    let subtitle: String?
    let uiFont: LeanFont
    let isDark: Bool
    var headingWeight: LeanFontWeight = .medium
    var bodyWeight: LeanFontWeight = .regular
    @ViewBuilder let control: () -> Control

    @State private var isRowHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(uiFont.font(size: 13, weight: headingWeight.fontWeight))
                    .foregroundColor(isDark ? Color(white: 0.94) : Color(white: 0.12))

                if let subtitle {
                    Text(subtitle)
                        .font(uiFont.font(size: 11.5, weight: bodyWeight.fontWeight))
                        .foregroundColor(isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.48))
                }
            }

            Spacer(minLength: 16)
            control()
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
    }
}
