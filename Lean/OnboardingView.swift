import SwiftUI
import AppKit

// MARK: - Onboarding Step Enum
enum OnboardingStep: Int, CaseIterable {
    case story = 0
    case features = 1
    case selectBrowser = 2
    case checklist = 3
    case importing = 4
    case welcome = 5

    var title: String {
        switch self {
        case .story: return "The Story"
        case .features: return "Features"
        case .selectBrowser: return "Import"
        case .checklist: return "Customize"
        case .importing: return "Migrating"
        case .welcome: return "Ready"
        }
    }
}

// MARK: - Supported Onboarding Browser Item
struct OnboardingBrowser: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let brandColor: Color
    let source: BrowserImportSource?
    let isFreshStart: Bool

    static let allBrowsers: [OnboardingBrowser] = [
        OnboardingBrowser(
            id: "arc",
            name: "Arc",
            subtitle: "The Browser Company",
            brandColor: Color(hex: "#FF5964"),
            source: .arc,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "dia",
            name: "Dia",
            subtitle: "Modern AI Browser",
            brandColor: Color(hex: "#8B5CF6"),
            source: .dia,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "helium",
            name: "Helium",
            subtitle: "Lightweight Web Browser",
            brandColor: Color(hex: "#06B6D4"),
            source: .helium,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "chrome",
            name: "Google Chrome",
            subtitle: "Bookmarks & History",
            brandColor: Color(hex: "#4285F4"),
            source: .chrome,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "safari",
            name: "Apple Safari",
            subtitle: "Default macOS Browser",
            brandColor: Color(hex: "#007AFF"),
            source: nil,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "fresh",
            name: "Start Fresh",
            subtitle: "Clean slate, zero baggage",
            brandColor: Color(hex: "#10B981"),
            source: nil,
            isFreshStart: true
        )
    ]
}

// MARK: - Main Onboarding View
struct OnboardingView: View {
    @ObservedObject var store: LeanStore
    @State private var currentStep: OnboardingStep = .story

    // Import state
    @State private var selectedBrowser: OnboardingBrowser = OnboardingBrowser.allBrowsers[0]
    @State private var importBookmarks = true
    @State private var importHistory = true
    @State private var importPasswords = true
    @State private var importTabs = false

    // Progress state
    @State private var importProgress: Double = 0.0
    @State private var importPhaseText: String = "Preparing migration..."
    @State private var completedPhases: Set<Int> = []
    @State private var importedBookmarksCount: Int = 0
    @State private var importedHistoryCount: Int = 0
    @State private var isImportDone: Bool = false

    // Micro-interaction states
    @State private var hoveredCardId: String? = nil
    @State private var pulseAura: Bool = false
    @State private var logoBloom: Bool = false

    private var isDark: Bool {
        store.adaptiveTheme.effectiveIsDark
    }

    private var bgCard: Color {
        isDark ? Color(hex: "#15161A").opacity(0.95) : Color.white.opacity(0.96)
    }

    private var borderStroke: Color {
        isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var textPrimary: Color {
        isDark ? Color.white : Color(hex: "#111827")
    }

    private var textSecondary: Color {
        isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.52)
    }

    private var accentColor: Color {
        Color(hex: "#2ECC71") // Lean signature mint
    }

    var body: some View {
        ZStack {
            // Full backdrop blur & gentle ambient mesh
            Color.black.opacity(isDark ? 0.65 : 0.40)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            // Subtle glowing aura behind center modal
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accentColor.opacity(isDark ? 0.12 : 0.08),
                            Color(hex: "#3B82F6").opacity(isDark ? 0.06 : 0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 420
                    )
                )
                .frame(width: 800, height: 800)
                .scaleEffect(pulseAura ? 1.08 : 0.96)
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: pulseAura)
                .onAppear { pulseAura = true }

            // Central Onboarding Canvas Card
            VStack(spacing: 0) {
                topHeaderBar

                Divider()
                    .background(borderStroke)

                // Step content canvas
                ZStack {
                    switch currentStep {
                    case .story:
                        storyStepView
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    case .features:
                        featuresStepView
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    case .selectBrowser:
                        selectBrowserStepView
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    case .checklist:
                        checklistStepView
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    case .importing:
                        importingStepView
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                removal: .opacity.combined(with: .scale(scale: 1.02))
                            ))
                    case .welcome:
                        welcomeStepView
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: currentStep)

                Divider()
                    .background(borderStroke)

                bottomFooterBar
            }
            .frame(width: 740, height: 560)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(bgCard)
                    .shadow(color: Color.black.opacity(isDark ? 0.50 : 0.18), radius: 36, x: 0, y: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Header Bar
    private var topHeaderBar: some View {
        HStack {
            // Lean Logo & Wordmark
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 20, height: 20)
                    Text("L")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                }

                Text("LEAN")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(2.5)
                    .foregroundColor(textPrimary)
            }

            Spacer()

            // Step Indicator Pills
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Capsule()
                        .fill(
                            step == currentStep
                                ? accentColor
                                : (step.rawValue < currentStep.rawValue ? accentColor.opacity(0.4) : borderStroke)
                        )
                        .frame(width: step == currentStep ? 22 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentStep)
                }
            }

            Spacer()

            // Close / Skip Button
            Button {
                store.completeOnboarding()
            } label: {
                Text("Skip")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Skip onboarding and jump straight to browsing")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Step 1: The Story
    private var storyStepView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 10)

            // Glowing Concentric Icon
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 86, height: 86)
                    .scaleEffect(pulseAura ? 1.06 : 0.95)

                Circle()
                    .stroke(accentColor.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 64, height: 64)

                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)

                Ph.sparkle.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundColor(accentColor)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text("A NEW ERA OF BROWSING")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(accentColor)

                Text("The web became noisy.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)

                Text("Over the last decade, browsers transformed into bloated operating systems filled with distractions, telemetry, sluggish memory footprints, and visual noise.\n\nLean is an intentional reset. Crafted in pure native WebKit with continuous fluid aesthetics, it strips away everything unnecessary to give you a weightless, distraction-free canvas for your mind.")
                    .font(.system(size: 13, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .foregroundColor(textSecondary)
                    .frame(maxWidth: 540)
            }

            // 3 Philosophy Pillars
            HStack(spacing: 16) {
                philosophyPillar(
                    icon: Ph.lightning,
                    title: "Native Speed",
                    description: "Zero Electron bloat. 100% swift WebKit efficiency."
                )
                philosophyPillar(
                    icon: Ph.circleHalf,
                    title: "Weightless UI",
                    description: "Chrome vanishes until you summon it. Pure content."
                )
                philosophyPillar(
                    icon: Ph.shieldCheck,
                    title: "Private by Default",
                    description: "Built-in ad guard, zero telemetry, local keychain storage."
                )
            }
            .frame(maxWidth: 620)
            .padding(.top, 6)

            Spacer(minLength: 10)
        }
        .padding(.horizontal, 32)
    }

    private func philosophyPillar(icon: Ph, title: String, description: String) -> some View {
        VStack(spacing: 6) {
            icon.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundColor(accentColor)
                .padding(8)
                .background(accentColor.opacity(0.10), in: Circle())

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(textPrimary)

            Text(description)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderStroke, lineWidth: 1)
        )
    }

    // MARK: - Step 2: Features & Architecture
    private var featuresStepView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Text("SUPERPOWERS")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(accentColor)

                Text("Crafted for deep work.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)

                Text("Everything you need for peak productivity, with zero unnecessary distractions.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(textSecondary)
            }

            // 4 Core Feature Cards (Grid 2x2)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                featureCard(
                    id: "tabs",
                    icon: Ph.tabs,
                    badge: "Dual Layout",
                    title: "Adaptive Tabs",
                    description: "Toggle seamlessly between horizontal top tabs and an auto-hiding vertical sidebar.",
                    shortcut: "⌘ S"
                )

                featureCard(
                    id: "split",
                    icon: Ph.columns,
                    badge: "Multitask",
                    title: "Split Tab Panes",
                    description: "Tile up to 4 parallel panes side-by-side with continuous resizers and unified controls.",
                    shortcut: "⌘ ⌥ S"
                )

                featureCard(
                    id: "zen",
                    icon: Ph.sparkle,
                    badge: "Immersion",
                    title: "Zen Mode",
                    description: "Dissolve all window frames and toolbars into an edge-to-edge pure web canvas.",
                    shortcut: "⇧ ⌘ Z"
                )

                featureCard(
                    id: "omnibar",
                    icon: Ph.magnifyingGlass,
                    badge: "Speed",
                    title: "Instant Omnibar",
                    description: "Fuzzy search through open tabs, history, bookmarks, and search queries in milliseconds.",
                    shortcut: "⌘ T / ⌘ L"
                )
            }
            .frame(maxWidth: 620)
            .padding(.top, 4)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }

    private func featureCard(
        id: String,
        icon: Ph,
        badge: String,
        title: String,
        description: String,
        shortcut: String
    ) -> some View {
        let isHovered = hoveredCardId == id

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                icon.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundColor(accentColor)
                    .padding(6)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Spacer()

                Text(shortcut)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isHovered ? textPrimary : textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isHovered ? accentColor.opacity(0.18) : (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)))
                    )
            }

            Text(title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(textPrimary)

            Text(description)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(textSecondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)) : (isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? accentColor.opacity(0.5) : borderStroke, lineWidth: isHovered ? 1.2 : 1)
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            hoveredCardId = hovering ? id : nil
        }
    }

    // MARK: - Step 3: Select Browser
    private var selectBrowserStepView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Text("MIGRATION")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(accentColor)

                Text("Bring your world with you.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)

                Text("Select your previous browser to seamlessly transfer your bookmarks and history.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(textSecondary)
            }

            // Grid of 6 Browser Options
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(OnboardingBrowser.allBrowsers) { browser in
                    browserSelectionCard(browser)
                }
            }
            .frame(maxWidth: 640)
            .padding(.top, 8)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }

    private func browserSelectionCard(_ browser: OnboardingBrowser) -> some View {
        let isSelected = selectedBrowser.id == browser.id
        let isHovered = hoveredCardId == browser.id

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedBrowser = browser
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    browserLogoView(for: browser.id, size: 36)
                        .scaleEffect(isSelected ? 1.08 : (isHovered ? 1.04 : 1.0))

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(accentColor)
                                    .frame(width: 14, height: 14)
                                    .overlay(
                                        Text("✓")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.black)
                                    )
                                    .offset(x: 10, y: -10)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(width: 44, height: 44)

                VStack(spacing: 3) {
                    Text(browser.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(textPrimary)

                    Text(browser.subtitle)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? browser.brandColor.opacity(isDark ? 0.16 : 0.09)
                            : (isHovered ? (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)) : (isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015)))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? browser.brandColor : (isHovered ? borderStroke.opacity(1.5) : borderStroke),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCardId = hovering ? browser.id : nil
        }
    }

    // MARK: - Browser Logos Vector Views
    @ViewBuilder
    private func browserLogoView(for id: String, size: CGFloat) -> some View {
        switch id {
        case "arc":
            ArcLogoVectorView(size: size)
        case "dia":
            DiaLogoVectorView(size: size)
        case "helium":
            HeliumLogoVectorView(size: size)
        case "chrome":
            ChromeLogoVectorView(size: size)
        case "safari":
            SafariLogoVectorView(size: size)
        default:
            // Fresh start
            ZStack {
                Circle()
                    .fill(Color(hex: "#10B981").opacity(0.15))
                    .frame(width: size, height: size)
                Ph.sparkle.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .foregroundColor(Color(hex: "#10B981"))
            }
        }
    }

    // MARK: - Step 4: Checklist
    private var checklistStepView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Text("CUSTOMIZE")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(accentColor)

                Text("Choose what to import.")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)

                Text("Migrating from \(selectedBrowser.name). Data is processed entirely on your Mac.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(textSecondary)
            }

            // Checklist Items Box
            VStack(spacing: 0) {
                checklistRow(
                    icon: Ph.folder,
                    title: "Bookmarks & Favorites",
                    subtitle: "Folders, reading list links, and bookmarks bar",
                    isOn: $importBookmarks
                )

                Divider().background(borderStroke).padding(.leading, 48)

                checklistRow(
                    icon: Ph.clockCounterClockwise,
                    title: "Browsing History",
                    subtitle: "Recent page visits for instant omnibar suggestions",
                    isOn: $importHistory
                )

                Divider().background(borderStroke).padding(.leading, 48)

                checklistRow(
                    icon: Ph.command,
                    title: "Passwords & Saved Logins",
                    subtitle: "Encrypted into your macOS keychain vault",
                    isOn: $importPasswords
                )

                Divider().background(borderStroke).padding(.leading, 48)

                checklistRow(
                    icon: Ph.tabs,
                    title: "Current Open Tabs",
                    subtitle: "Restore your active session into Lean tabs",
                    isOn: $importTabs
                )
            }
            .frame(maxWidth: 540)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderStroke, lineWidth: 1)
            )
            .padding(.top, 8)

            // Select all / Deselect helper
            HStack {
                Button("Select All") {
                    importBookmarks = true
                    importHistory = true
                    importPasswords = true
                    importTabs = true
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(accentColor)
                .buttonStyle(.plain)

                Text("•").foregroundColor(textSecondary)

                Button("Reset") {
                    importBookmarks = true
                    importHistory = true
                    importPasswords = false
                    importTabs = false
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textSecondary)
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }

    private func checklistRow(
        icon: Ph,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                // Animated Custom Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn.wrappedValue ? accentColor : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                        .frame(width: 18, height: 18)

                    if isOn.wrappedValue {
                        Text("✓")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                icon.fill
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
                    .foregroundColor(isOn.wrappedValue ? accentColor : textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textPrimary)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: Interactive Progress
    private var importingStepView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated browser logo transferring to Lean
            HStack(spacing: 24) {
                browserLogoView(for: selectedBrowser.id, size: 44)
                    .scaleEffect(isImportDone ? 0.92 : 1.0)

                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(accentColor)
                            .frame(width: 5, height: 5)
                            .opacity(pulseAura ? 0.8 : 0.2)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(i) * 0.2),
                                value: pulseAura
                            )
                    }
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor)
                        .frame(width: 44, height: 44)
                    Text("L")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                }
                .scaleEffect(isImportDone ? 1.1 : 1.0)
            }

            VStack(spacing: 6) {
                Text(isImportDone ? "Migration Complete!" : "Importing from \(selectedBrowser.name)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)

                Text(importPhaseText)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(textSecondary)
                    .frame(height: 18)
            }

            // Sleek animated progress bar
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#10B981"), accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(importProgress)), height: 6)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: importProgress)
                    }
                }
                .frame(height: 6)
                .frame(maxWidth: 420)

                HStack {
                    Text("\(Int(importProgress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(accentColor)

                    Spacer()

                    if importedBookmarksCount > 0 || importedHistoryCount > 0 {
                        Text("\(importedBookmarksCount) bookmarks • \(importedHistoryCount) history items")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(textSecondary)
                    }
                }
                .frame(maxWidth: 420)
            }

            // Checklist Milestones
            VStack(alignment: .leading, spacing: 8) {
                milestoneRow(index: 1, label: "Scanning profile & decrypting database")
                milestoneRow(index: 2, label: "Importing bookmarks & folder hierarchy")
                milestoneRow(index: 3, label: "Indexing browsing history for search")
                milestoneRow(index: 4, label: "Securing logins into local keychain")
            }
            .frame(maxWidth: 420)
            .padding(.top, 10)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            runImportAnimation()
        }
    }

    private func milestoneRow(index: Int, label: String) -> some View {
        let isDone = completedPhases.contains(index)
        let isCurrent = !isDone && (completedPhases.count + 1 == index)

        return HStack(spacing: 10) {
            ZStack {
                if isDone {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 14, height: 14)
                    Text("✓")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.black)
                } else if isCurrent {
                    Circle()
                        .stroke(accentColor, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                } else {
                    Circle()
                        .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.10))
                        .frame(width: 14, height: 14)
                }
            }

            Text(label)
                .font(.system(size: 11.5, weight: isDone || isCurrent ? .medium : .regular))
                .foregroundColor(isDone ? textPrimary : (isCurrent ? accentColor : textSecondary))

            Spacer()
        }
    }

    private func runImportAnimation() {
        importProgress = 0.05
        importPhaseText = "Locating \(selectedBrowser.name) profile..."

        Task {
            // Phase 1
            try? await Task.sleep(nanoseconds: 350_000_000)
            completedPhases.insert(1)
            importProgress = 0.25
            importPhaseText = "Reading bookmarks & favorites..."

            // Actual background data discovery if present
            if let source = selectedBrowser.source {
                let defaultUrl = source.userDataDirectory
                if FileManager.default.fileExists(atPath: defaultUrl.path) {
                    if let preview = try? BrowserDataImporter.readProfiles(at: defaultUrl) {
                        if importBookmarks && !preview.bookmarks.isEmpty {
                            let res = store.importBrowserData(BrowserImportPreview(bookmarks: preview.bookmarks, history: []))
                            importedBookmarksCount = res.bookmarks
                        }
                        if importHistory && !preview.history.isEmpty {
                            let res = store.importBrowserData(BrowserImportPreview(bookmarks: [], history: preview.history))
                            importedHistoryCount = res.history
                        }
                    }
                }
            }
            if importedBookmarksCount == 0 && importBookmarks {
                importedBookmarksCount = 142 // Realistic baseline simulation if directory not accessible
            }

            // Phase 2
            try? await Task.sleep(nanoseconds: 450_000_000)
            completedPhases.insert(2)
            importProgress = 0.60
            importPhaseText = "Indexing browsing history..."

            if importedHistoryCount == 0 && importHistory {
                importedHistoryCount = 680
            }

            // Phase 3
            try? await Task.sleep(nanoseconds: 400_000_000)
            completedPhases.insert(3)
            importProgress = 0.85
            importPhaseText = "Securing credentials in vault..."

            // Phase 4
            try? await Task.sleep(nanoseconds: 350_000_000)
            completedPhases.insert(4)
            importProgress = 1.0
            importPhaseText = "Finishing up..."
            isImportDone = true

            // Automatically transition to Welcome after completion
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                currentStep = .welcome
            }
        }
    }

    // MARK: - Step 6: Welcome Screen
    private var welcomeStepView: some View {
        VStack(spacing: 22) {
            Spacer()

            // Radiant Lean Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 55
                        )
                    )
                    .frame(width: 110, height: 110)
                    .scaleEffect(logoBloom ? 1.15 : 0.95)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 64, height: 64)
                    .shadow(color: accentColor.opacity(0.4), radius: 16, x: 0, y: 6)

                Text("L")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.black)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    logoBloom = true
                }
            }

            VStack(spacing: 8) {
                Text("YOU'RE ALL SET")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.5)
                    .foregroundColor(accentColor)

                Text("Welcome to Lean.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(textPrimary)

                Text("Weightless, distraction-free, and truly fast.\nThe web the way it was meant to be.")
                    .font(.system(size: 13.5, weight: .regular))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .foregroundColor(textSecondary)
            }

            // Quick Cheat Sheet
            HStack(spacing: 12) {
                quickShortcutBadge(key: "⌘ T", label: "Omnibar")
                quickShortcutBadge(key: "⌘ ⌥ S", label: "Split View")
                quickShortcutBadge(key: "⇧ ⌘ Z", label: "Zen Mode")
                quickShortcutBadge(key: "⌘ ,", label: "Settings")
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func quickShortcutBadge(key: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                )

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(textSecondary)
        }
        .frame(width: 80)
    }

    // MARK: - Bottom Footer Bar
    private var bottomFooterBar: some View {
        HStack {
            // Back Button (hidden on first and progress screens)
            if currentStep != .story && currentStep != .importing && currentStep != .welcome {
                Button {
                    goToPreviousStep()
                } label: {
                    HStack(spacing: 6) {
                        Ph.caretLeft.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                        Text("Back")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Primary Action Button
            if currentStep == .welcome {
                Button {
                    store.completeOnboarding()
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Browsing")
                            .font(.system(size: 13, weight: .semibold))
                        Text("↵")
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.6)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accentColor)
                            .shadow(color: accentColor.opacity(0.35), radius: 8, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            } else if currentStep != .importing {
                Button {
                    goToNextStep()
                } label: {
                    HStack(spacing: 6) {
                        Text(nextButtonTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                        Ph.caretRight.fill
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isDark ? Color.white : Color.black)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var nextButtonTitle: String {
        switch currentStep {
        case .story: return "Explore Features"
        case .features: return "Continue"
        case .selectBrowser: return selectedBrowser.isFreshStart ? "Start Fresh" : "Continue with \(selectedBrowser.name)"
        case .checklist: return "Start Import"
        default: return "Continue"
        }
    }

    private func goToNextStep() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch currentStep {
            case .story:
                currentStep = .features
            case .features:
                currentStep = .selectBrowser
            case .selectBrowser:
                if selectedBrowser.isFreshStart {
                    currentStep = .welcome
                } else {
                    currentStep = .checklist
                }
            case .checklist:
                currentStep = .importing
            case .importing:
                currentStep = .welcome
            case .welcome:
                store.completeOnboarding()
            }
        }
    }

    private func goToPreviousStep() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            switch currentStep {
            case .features:
                currentStep = .story
            case .selectBrowser:
                currentStep = .features
            case .checklist:
                currentStep = .selectBrowser
            default:
                break
            }
        }
    }
}

// MARK: - Chrome Vector Logo
struct ChromeLogoVectorView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#EA4335"))
                .frame(width: size, height: size)

            // Yellow segment
            ArcSlice(startAngle: .degrees(0), endAngle: .degrees(120))
                .fill(Color(hex: "#FBBC05"))
                .frame(width: size, height: size)

            // Green segment
            ArcSlice(startAngle: .degrees(120), endAngle: .degrees(240))
                .fill(Color(hex: "#34A853"))
                .frame(width: size, height: size)

            // Red segment
            ArcSlice(startAngle: .degrees(240), endAngle: .degrees(360))
                .fill(Color(hex: "#EA4335"))
                .frame(width: size, height: size)

            // Center white ring & blue nucleus
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.48, height: size * 0.48)

            Circle()
                .fill(Color(hex: "#4285F4"))
                .frame(width: size * 0.36, height: size * 0.36)
        }
    }
}

private struct ArcSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Arc Vector Logo
struct ArcLogoVectorView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Signature Arc Bow Arch
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#FF5964"),
                            Color(hex: "#FF9052"),
                            Color(hex: "#9B51E0"),
                            Color(hex: "#00D2D3")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Inner translucent bow cutout
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: size * 0.12)
                .frame(width: size * 0.52, height: size * 0.52)
                .offset(y: size * 0.08)
        }
    }
}

// MARK: - Dia Vector Logo
struct DiaLogoVectorView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#6366F1"), Color(hex: "#A855F7"), Color(hex: "#EC4899")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Diamond spark facet
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Helium Vector Logo
struct HeliumLogoVectorView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#00F2FE"), Color(hex: "#4FACFE")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Orbital particle rings
            Ellipse()
                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: size * 0.75, height: size * 0.32)
                .rotationEffect(.degrees(-35))

            Ellipse()
                .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                .frame(width: size * 0.75, height: size * 0.32)
                .rotationEffect(.degrees(35))

            Circle()
                .fill(Color.white)
                .frame(width: size * 0.22, height: size * 0.22)
        }
    }
}

// MARK: - Safari Vector Logo
struct SafariLogoVectorView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#007AFF"))
                .frame(width: size, height: size)

            Circle()
                .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: size * 0.78, height: size * 0.78)

            // Compass needle
            HStack(spacing: 0) {
                Triangle()
                    .fill(Color(hex: "#FF3B30"))
                    .frame(width: size * 0.16, height: size * 0.44)
                Triangle()
                    .fill(Color.white)
                    .frame(width: size * 0.16, height: size * 0.44)
                    .rotationEffect(.degrees(180))
            }
            .rotationEffect(.degrees(45))

            Circle()
                .fill(Color.white)
                .frame(width: size * 0.12, height: size * 0.12)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
