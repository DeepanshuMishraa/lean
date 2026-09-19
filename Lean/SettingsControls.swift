import SwiftUI

// MARK: - Font Picker

struct FontPickerRow: View {
    let title: String
    @Binding var selection: LeanFont
    let uiFont: LeanFont
    let isDark: Bool

    @State private var isPresented = false

    var body: some View {
        HStack {
            Text(title)
                .font(uiFont.font(size: 13, weight: .medium))
                .foregroundColor(primaryText)

            Spacer()

            Button {
                isPresented.toggle()
            } label: {
                HStack {
                    Text(selection.rawValue)
                        .font(uiFont.font(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(primaryText)
                .padding(.horizontal, 10)
                .frame(width: 160, height: 32)
                .background(
                    isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented) {
                VStack(spacing: 2) {
                    ForEach(LeanFont.allCases) { choice in
                        Button {
                            selection = choice
                            isPresented = false
                        } label: {
                            HStack {
                                Text(choice.rawValue)
                                    .font(choice.font(size: 14, weight: .medium))
                                Spacer()
                                if selection == choice {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundColor(primaryText)
                            .padding(.horizontal, 10)
                            .frame(width: 220, height: 32)
                            .background(
                                selection == choice
                                    ? (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var primaryText: Color {
        isDark ? Color(white: 0.96) : Color(white: 0.12)
    }
}

// MARK: - Section Container

struct SettingsSection<Content: View>: View {
    let title: String
    let uiFont: LeanFont
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(uiFont.font(size: 11, weight: .bold))
                .foregroundColor(Color(white: 0.45))
                .textCase(.uppercase)
                .tracking(0.7)

            content()
        }
    }
}

// MARK: - Custom Minimal Segmented Picker (Non-native, bespoke craft)

struct SegmentOption {
    let id: String
    let label: String
    let icon: String
}

struct CustomSegmentedPicker: View {
    let options: [SegmentOption]
    let selectedId: String
    let isDark: Bool
    let uiFont: LeanFont
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.id) { opt in
                let isSelected = opt.id == selectedId
                Button(action: {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        onSelect(opt.id)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: opt.icon)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        Text(opt.label)
                            .font(uiFont.font(size: 12, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(
                        isSelected
                            ? (isDark ? .white : Color.black)
                            : (isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        isSelected
                            ? (isDark ? Color(red: 44/255, green: 44/255, blue: 48/255) : Color.white)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSelected
                                    ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: isSelected && !isDark ? Color.black.opacity(0.06) : Color.clear,
                        radius: 2,
                        y: 1
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            isDark ? Color(red: 26/255, green: 26/255, blue: 29/255) : Color(red: 236/255, green: 236/255, blue: 240/255),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Custom Switch / Toggle (Completely Non-Native, High-End Pill Design)

struct CustomToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let isDark: Bool
    let uiFont: LeanFont

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(uiFont.font(size: 13, weight: .medium))
                    .foregroundColor(isDark ? Color.white : Color(white: 0.12))
                Text(subtitle)
                    .font(uiFont.font(size: 11))
                    .foregroundColor(isDark ? Color(white: 0.50) : Color(white: 0.48))
            }

            Spacer()

            // Bespoke sleek capsule switch
            Button(action: {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                    isOn.toggle()
                }
            }) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(
                            isOn
                                ? (isDark ? Color.white : Color.black)
                                : (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
                        )
                        .frame(width: 38, height: 22)

                    Circle()
                        .fill(
                            isOn
                                ? (isDark ? Color.black : Color.white)
                                : (isDark ? Color.white.opacity(0.7) : Color.white)
                        )
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .shadow(color: Color.black.opacity(0.15), radius: 1, y: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                isOn.toggle()
            }
        }
    }
}
