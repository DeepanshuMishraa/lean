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

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                let isSelected = opt.id == selectedId
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
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
                    .foregroundColor(
                        isSelected
                            ? (isDark ? Color.white : Color.black)
                            : (isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.14) : Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.5)
                                )
                                .shadow(color: isDark ? Color.clear : Color.black.opacity(0.05), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "activeSegment", in: segmentAnimation)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(
            isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.05), lineWidth: 0.5)
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

            // Tactile Minimal Capsule Switch
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? (isDark ? Color.white : Color.black)
                            : (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
                    )
                    .frame(width: 36, height: 21)

                Circle()
                    .fill(
                        isOn
                            ? (isDark ? Color.black : Color.white)
                            : (isDark ? Color.white.opacity(0.75) : Color.white)
                    )
                    .frame(width: 15, height: 15)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.18), radius: 1, y: 1)
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

// MARK: - Font Picker Row
struct FontPickerRow: View {
    let title: String
    let subtitle: String?
    @Binding var selection: LeanFont
    let uiFont: LeanFont
    let isDark: Bool

    @State private var isPresented = false
    @State private var isHovered = false

    init(
        title: String,
        subtitle: String? = nil,
        selection: Binding<LeanFont>,
        uiFont: LeanFont,
        isDark: Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.uiFont = uiFont
        self.isDark = isDark
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(uiFont.font(size: 13, weight: .medium))
                    .foregroundColor(primaryText)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(uiFont.font(size: 11.5))
                        .foregroundColor(secondaryText)
                }
            }

            Spacer(minLength: 16)

            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(selection.rawValue)
                        .font(selection.font(size: 12.5, weight: .medium))
                        .foregroundColor(primaryText)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(secondaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(spacing: 1) {
                    ForEach(LeanFont.allCases) { fontChoice in
                        let isChosen = selection == fontChoice
                        Button {
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.8)) {
                                selection = fontChoice
                            }
                            isPresented = false
                        } label: {
                            HStack(spacing: 10) {
                                Text(fontChoice.rawValue)
                                    .font(fontChoice.font(size: 13, weight: isChosen ? .semibold : .regular))
                                Spacer()
                                if isChosen {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(primaryText)
                                }
                            }
                            .foregroundColor(primaryText)
                            .padding(.horizontal, 10)
                            .frame(width: 200, height: 30)
                            .background(
                                isChosen
                                    ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(5)
                .background(isDark ? Color(white: 0.12) : Color(white: 0.98))
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
    }

    private var primaryText: Color {
        isDark ? Color(white: 0.94) : Color(white: 0.12)
    }

    private var secondaryText: Color {
        isDark ? Color(white: 0.50) : Color(white: 0.48)
    }
}

// MARK: - Frame Width Picker Row
struct FrameWidthPickerRow: View {
    @ObservedObject var store: LeanStore
    let isDark: Bool
    let uiFont: LeanFont

    private let widths: [(label: String, width: CGFloat, previewLine: CGFloat)] = [
        ("Thin", 5.0, 1.5),
        ("Normal", 8.0, 3.0),
        ("Thick", 12.0, 5.0)
    ]

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
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                            store.windowBorderWidth = item.width
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Capsule()
                                .fill(isSelected ? (isDark ? Color.white : Color.black) : (isDark ? Color.white.opacity(0.4) : Color.black.opacity(0.35)))
                                .frame(width: 10, height: item.previewLine)

                            Text(item.label)
                                .font(uiFont.font(size: 11.5, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundColor(
                            isSelected
                                ? (isDark ? Color.white : Color.black)
                                : (isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                        )
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(
                            isSelected
                                ? (isDark ? Color.white.opacity(0.14) : Color.white)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    isSelected
                                        ? (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                                        : Color.clear,
                                    lineWidth: 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
