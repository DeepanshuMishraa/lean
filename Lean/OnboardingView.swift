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

    var stepNumber: String {
        switch self {
        case .story: return "1 / 4"
        case .features: return "2 / 4"
        case .selectBrowser: return "3 / 4"
        case .checklist: return "4 / 4"
        case .importing: return "Migrating"
        case .welcome: return "Ready"
        }
    }

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

// MARK: - Onboarding Import Phase
/// Where the importing step stands. `.working` is the progress view;
/// everything else replaces it with the honest state: what is needed, what
/// failed, or what actually landed.
enum OnboardingImportPhase: Equatable {
    case working
    case needsFolder
    case safariNotice
    case failed(String)
    case finished(summary: String)
}

// MARK: - Supported Browser Option
struct OnboardingBrowser: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let source: BrowserImportSource?
    let isFreshStart: Bool

    static let allBrowsers: [OnboardingBrowser] = [
        OnboardingBrowser(
            id: "arc",
            name: "Arc",
            subtitle: "The Browser Company",
            source: .arc,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "dia",
            name: "Dia",
            subtitle: "The Browser Company",
            source: .dia,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "helium",
            name: "Helium",
            subtitle: "Lightweight Browser",
            source: .helium,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "chrome",
            name: "Google Chrome",
            subtitle: "Google",
            source: .chrome,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "safari",
            name: "Safari",
            subtitle: "Apple",
            source: nil,
            isFreshStart: false
        ),
        OnboardingBrowser(
            id: "fresh",
            name: "Start Fresh",
            subtitle: "Clean slate",
            source: nil,
            isFreshStart: true
        )
    ]
}

// MARK: - Main Onboarding View (Rendered directly on page)
struct OnboardingView: View {
    @ObservedObject var store: LeanStore
    @State private var currentStep: OnboardingStep = .story
    @State private var navigationDirection: Int = 1
    @State private var keyMonitor: Any? = nil

    // Selection & Checklist
    @State private var selectedBrowser: OnboardingBrowser = OnboardingBrowser.allBrowsers[0]
    @State private var importBookmarks = true
    @State private var importHistory = true
    @State private var importPasswords = true

    // Import run state — everything here is real: no sample counts, no
    // simulated progress. Either the data lands in Lean or the step says why.
    @State private var importPhase: OnboardingImportPhase = .working
    @State private var importStartedToken = UUID()

    // Progress State
    @State private var importProgress: Double = 0.0
    @State private var importStatus: String = "Connecting..."
    @State private var importedBookmarksCount: Int = 0
    @State private var importedHistoryCount: Int = 0

    // Hover State
    @State private var hoveredItem: String? = nil

    private var isDark: Bool {
        store.adaptiveTheme.effectiveIsDark
    }

    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    private var rowBackground: Color {
        isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
    }

    private var primaryText: Color {
        isDark ? Color.white : Color.black
    }

    private var secondaryText: Color {
        isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.50)
    }

    private var tertiaryText: Color {
        isDark ? Color.white.opacity(0.30) : Color.black.opacity(0.30)
    }

    private var accent: Color {
        Color(red: 0.18, green: 0.80, blue: 0.44)
    }

    var body: some View {
        ZStack {
            // Page canvas background matching Lean's native surface
            store.themeColors.windowBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                Rectangle()
                    .fill(cardBorder)
                    .frame(height: 1)

                // Central step canvas: centered with comfortable max-width and fluid sliding animation
                ZStack {
                    Group {
                        switch currentStep {
                        case .story:
                            storyStepView
                        case .features:
                            featuresStepView
                        case .selectBrowser:
                            selectBrowserStepView
                        case .checklist:
                            checklistStepView
                        case .importing:
                            importingStepView
                        case .welcome:
                            welcomeStepView
                        }
                    }
                    .frame(maxWidth: 680)
                    .frame(maxHeight: .infinity)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .offset(x: navigationDirection >= 0 ? 30 : -30)),
                            removal: .opacity
                                .combined(with: .offset(x: navigationDirection >= 0 ? -30 : 30))
                        )
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Rectangle()
                    .fill(cardBorder)
                    .frame(height: 1)

                footerBar
            }
        }
        .onAppear {
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Clearance for macOS traffic light buttons
            Spacer().frame(width: store.scaled(72))

            // Wordmark
            HStack(spacing: 7) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)

                Text("LEAN")
                    .font(store.headingFont(size: 11.5))
                    .tracking(2.0)
                    .foregroundColor(primaryText)
            }

            Spacer()

            // Smooth Story Progress Indicator
            if currentStep != .importing && currentStep != .welcome {
                HStack(spacing: 6) {
                    ForEach(0..<4) { index in
                        let step = OnboardingStep(rawValue: index)!
                        Button {
                            navigateToStep(step)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(currentStep.rawValue == index ? accent : (currentStep.rawValue > index ? primaryText.opacity(0.6) : cardBorder.opacity(0.8)))
                                    .frame(width: currentStep.rawValue == index ? 6 : 5, height: currentStep.rawValue == index ? 6 : 5)

                                Text(step.title)
                                    .font(store.bodyFont(size: 10.5))
                                    .foregroundColor(currentStep.rawValue == index ? primaryText : (currentStep.rawValue > index ? secondaryText : tertiaryText))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(currentStep.rawValue == index ? (isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(currentStep == .importing)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: currentStep)
            }

            Spacer()

            // Skip Button
            Button {
                store.completeOnboarding()
            } label: {
                HStack(spacing: 4) {
                    Text("Skip")
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(secondaryText)

                    Text("Esc")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(tertiaryText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(cardBorder)
                        )
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: - Step 1: The Story
    private var storyStepView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("THE STORY")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(secondaryText)

                Text("A return to weightless browsing.")
                    .font(store.headingFont(size: 24))
                    .foregroundColor(primaryText)

                Text("Modern browsers became operating systems of noise—cluttered by telemetry, heavy runtimes, and visual distraction.\n\nLean was designed as a quiet canvas: pure native WebKit, instant responsiveness, and an interface that disappears the moment you start reading.")
                    .font(store.bodyFont(size: 13.5))
                    .lineSpacing(4.5)
                    .foregroundColor(secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3 Horizontal Minimalist Badges
            VStack(spacing: 10) {
                storyRow(
                    icon: LeanIcon.lightning,
                    title: "Native WebKit Engine",
                    detail: "Zero Chromium bloat. Instant startup and microsecond tab switching."
                )
                storyRow(
                    icon: LeanIcon.circleHalf,
                    title: "Vanishing Interface",
                    detail: "Toolbars retreat smoothly, giving 100% of your screen to the web."
                )
                storyRow(
                    icon: LeanIcon.shieldCheck,
                    title: "Private by Default",
                    detail: "Native tracker blocking and strictly local, encrypted keychain storage."
                )
            }
            .padding(.top, 4)

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 32)
    }

    private func storyRow(icon: LeanIcon, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            icon.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
                .foregroundColor(primaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(rowBackground)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(store.headingFont(size: 12.5))
                    .foregroundColor(primaryText)

                Text(detail)
                    .font(store.bodyFont(size: 11.5))
                    .foregroundColor(secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
    }

    // MARK: - Step 2: Architecture & Features
    private var featuresStepView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("ARCHITECTURE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(secondaryText)

                Text("Engineered for focus.")
                    .font(store.headingFont(size: 24))
                    .foregroundColor(primaryText)

                Text("Four core interactions tuned for deep work.")
                    .font(store.bodyFont(size: 13))
                    .foregroundColor(secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 4 Minimalist Rows
            VStack(spacing: 10) {
                featureRow(
                    id: "tabs",
                    icon: LeanIcon.tabs,
                    title: "Dual Tab Layout",
                    detail: "Switch between horizontal tabs and an auto-collapsing vertical sidebar.",
                    shortcut: "⌘ S"
                )

                featureRow(
                    id: "split",
                    icon: LeanIcon.columns,
                    title: "Split Tab Panes",
                    detail: "Tile up to 4 parallel panes side-by-side with proportional drag resizing.",
                    shortcut: "⌘ ⌥ S"
                )

                featureRow(
                    id: "zen",
                    icon: LeanIcon.sparkle,
                    title: "Zen Mode",
                    detail: "Dissolve all window chrome into an edge-to-edge pure page canvas.",
                    shortcut: "⇧ ⌘ Z"
                )

                featureRow(
                    id: "omnibar",
                    icon: LeanIcon.magnifyingGlass,
                    title: "Command Omnibar",
                    detail: "Fuzzy search through open tabs, history, and bookmarks instantly.",
                    shortcut: "⌘ T"
                )
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 32)
    }

    private func featureRow(id: String, icon: LeanIcon, title: String, detail: String, shortcut: String) -> some View {
        let isHovered = hoveredItem == id

        return HStack(spacing: 14) {
            icon.fill
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
                .foregroundColor(primaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? cardBorder : rowBackground)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(store.headingFont(size: 12.5))
                    .foregroundColor(primaryText)

                Text(detail)
                    .font(store.bodyFont(size: 11.5))
                    .foregroundColor(secondaryText)
            }

            Spacer()

            Text(shortcut)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundColor(secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(cardBorder)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? (isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)) : rowBackground)
        )
        .onHover { hovering in
            hoveredItem = hovering ? id : nil
        }
    }

    // MARK: - Step 3: Select Browser
    private var selectBrowserStepView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("MIGRATION")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(secondaryText)

                Text("Import your data.")
                    .font(store.headingFont(size: 24))
                    .foregroundColor(primaryText)

                Text("Select your previous browser to transfer bookmarks, history, and passwords.")
                    .font(store.bodyFont(size: 13))
                    .foregroundColor(secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 2-Column Grid of 6 Browsers with ACTUAL Official App Icons
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(OnboardingBrowser.allBrowsers) { browser in
                    browserCard(browser)
                }
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 32)
    }

    private func browserCard(_ browser: OnboardingBrowser) -> some View {
        let isSelected = selectedBrowser == browser
        let isHovered = hoveredItem == browser.id

        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                selectedBrowser = browser
            }
        } label: {
            HStack(spacing: 12) {
                // Official Application Icon
                Group {
                    if browser.isFreshStart {
                        ZStack {
                            Circle()
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                .frame(width: 32, height: 32)

                            LeanIcon.sparkle.fill
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .foregroundColor(primaryText)
                        }
                    } else {
                        BrowserIconProvider.image(for: browser.id)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.name)
                        .font(store.headingFont(size: 12.5))
                        .foregroundColor(primaryText)

                    Text(browser.subtitle)
                        .font(store.bodyFont(size: 10.5))
                        .foregroundColor(secondaryText)
                }

                Spacer()

                // Selection Radio Dot
                ZStack {
                    Circle()
                        .stroke(isSelected ? primaryText : secondaryText.opacity(0.3), lineWidth: 1.2)
                        .frame(width: 14, height: 14)

                    if isSelected {
                        Circle()
                            .fill(primaryText)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)) : (isHovered ? rowBackground.opacity(1.5) : rowBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? primaryText.opacity(0.4) : cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? browser.id : nil
        }
    }

    // MARK: - Step 4: Checklist
    private var checklistStepView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("CUSTOMIZE IMPORT")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(2.0)
                    .foregroundColor(secondaryText)

                Text("Choose what to migrate.")
                    .font(store.headingFont(size: 24))
                    .foregroundColor(primaryText)

                Text("Selected: \(selectedBrowser.name). All imported data remains 100% offline.")
                    .font(store.bodyFont(size: 13))
                    .foregroundColor(secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                checklistRow(
                    icon: LeanIcon.folder,
                    title: "Bookmarks & Favorites",
                    subtitle: "Folders, reading list, and pinned bookmark links",
                    isOn: $importBookmarks
                )

                Rectangle().fill(cardBorder).frame(height: 1).padding(.leading, 48)

                checklistRow(
                    icon: LeanIcon.clock,
                    title: "Browsing History",
                    subtitle: "Fast instant-search URL index and visited sites",
                    isOn: $importHistory
                )

                Rectangle().fill(cardBorder).frame(height: 1).padding(.leading, 48)

                checklistRow(
                    icon: LeanIcon.shieldCheck,
                    title: "Saved Passwords",
                    subtitle: "Decrypted from the browser and migrated into your private macOS keychain",
                    isOn: $importPasswords
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            )

            // Select all / Reset actions
            HStack(spacing: 10) {
                Button("Select All") {
                    importBookmarks = true
                    importHistory = true
                    importPasswords = true
                }
                .font(store.bodyFont(size: 11))
                .foregroundColor(primaryText)
                .buttonStyle(.plain)

                Text("•").foregroundColor(tertiaryText)

                Button("Reset") {
                    importBookmarks = true
                    importHistory = true
                    importPasswords = false
                }
                .font(store.bodyFont(size: 11))
                .foregroundColor(secondaryText)
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 2)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 32)
    }

    private func checklistRow(icon: LeanIcon, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                // Minimalist square checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isOn.wrappedValue ? primaryText : Color.clear)
                        .frame(width: 16, height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(isOn.wrappedValue ? primaryText : secondaryText.opacity(0.4), lineWidth: 1)
                        )

                    if isOn.wrappedValue {
                        Text("✓")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isDark ? .black : .white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(store.headingFont(size: 12.5))
                        .foregroundColor(primaryText)

                    Text(subtitle)
                        .font(store.bodyFont(size: 11))
                        .foregroundColor(secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: Importing (real data, real counts)
    private var importingStepView: some View {
        Group {
            switch importPhase {
            case .working:
                importingProgressView
            case .needsFolder:
                importAccessView(
                    title: "One permission needed.",
                    detail: "Lean is sandboxed, so it can't open \(selectedBrowser.name)'s data on its own. Point it at the \(selectedBrowser.name) data folder and it finds every profile inside.\n\nIt's usually at \(selectedBrowser.source?.grantDirectory.path ?? "your browser's data folder") — in the panel, press ⌘⇧G and paste that in, since Library stays hidden.",
                    primaryTitle: "Grant Access…",
                    primary: { grantBrowserFolder() },
                    secondaryTitle: "Skip Import",
                    secondary: { advanceToWelcome() }
                )
            case .safariNotice:
                importAccessView(
                    title: "Safari can't share automatically.",
                    detail: "Apple keeps Safari's data to itself. Export it first (Safari > File > Export > Bookmarks…), then bring the file in through Settings > Import Data.",
                    primaryTitle: "Continue",
                    primary: { advanceToWelcome() },
                    secondaryTitle: nil,
                    secondary: nil
                )
            case .failed(let reason):
                importAccessView(
                    title: "That didn't work.",
                    detail: reason,
                    primaryTitle: "Try Again",
                    primary: { restartImport() },
                    secondaryTitle: "Skip Import",
                    secondary: { advanceToWelcome() }
                )
            case .finished(let summary):
                importAccessView(
                    title: "Everything's in.",
                    detail: summary,
                    primaryTitle: "Continue",
                    primary: { advanceToWelcome() },
                    secondaryTitle: nil,
                    secondary: nil
                )
            }
        }
        .padding(.horizontal, 32)
        .onAppear {
            runImportProcess()
        }
    }

    /// The access/notice/failure/finished card: same canvas as the progress
    /// view so the step never jumps around.
    private func importAccessView(
        title: String,
        detail: String,
        primaryTitle: String,
        primary: @escaping () -> Void,
        secondaryTitle: String?,
        secondary: (() -> Void)?
    ) -> some View {
        VStack(spacing: 26) {
            Spacer()

            VStack(spacing: 8) {
                Text(title)
                    .font(store.headingFont(size: 20))
                    .foregroundColor(primaryText)

                Text(detail)
                    .font(store.bodyFont(size: 12.5))
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                if let secondaryTitle, let secondary {
                    Button(secondaryTitle, action: secondary)
                        .font(store.bodyFont(size: 12))
                        .foregroundColor(secondaryText)
                        .buttonStyle(.plain)
                }
                Button(primaryTitle, action: primary)
                    .font(store.headingFont(size: 12.5))
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(primaryText))
                    .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var importingProgressView: some View {
        VStack(spacing: 26) {
            Spacer()

            // Lean Signature Dot Matrix Loader
            DotMatrixLoader(color: primaryText, size: 28)

            VStack(spacing: 6) {
                Text("Importing from \(selectedBrowser.name)")
                    .font(store.headingFont(size: 20))
                    .foregroundColor(primaryText)

                Text(importStatus)
                    .font(store.bodyFont(size: 12.5))
                    .foregroundColor(secondaryText)
                    .frame(height: 20)
            }

            // Hairline Progress Bar
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(cardBorder)
                            .frame(height: 2)

                        Rectangle()
                            .fill(primaryText)
                            .frame(width: max(4, geo.size.width * CGFloat(importProgress)), height: 2)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: importProgress)
                    }
                }
                .frame(height: 2)
                .frame(maxWidth: 340)

                HStack {
                    Text("\(Int(importProgress * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryText)

                    Spacer()

                    if importedBookmarksCount > 0 || importedHistoryCount > 0 {
                        Text("\(importedBookmarksCount) bookmarks • \(importedHistoryCount) history")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(secondaryText)
                    }
                }
                .frame(maxWidth: 340)
            }

            Spacer()
        }
    }

    /// The needsFolder card's action: open the panel now rather than
    /// waiting. A grant restarts the run (the remembered bookmark feeds
    /// it); a dismissal leaves the card where it is.
    private func grantBrowserFolder() {
        guard let source = selectedBrowser.source else { return }
        Task { @MainActor in
            guard await requestImportFolder(for: source) != nil else { return }
            restartImport()
        }
    }

    private func restartImport() {
        importProgress = 0.05
        importStatus = "Connecting to profile..."
        importedBookmarksCount = 0
        importedHistoryCount = 0
        importPhase = .working
        importStartedToken = UUID()
        runImportProcess()
    }

    private func advanceToWelcome() {
        navigationDirection = 1
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            currentStep = .welcome
        }
    }

    private func runImportProcess() {
        let token = importStartedToken
        guard importPhase == .working else { return }

        // Nothing to read: a clean slate, or a browser that shares nothing.
        if selectedBrowser.isFreshStart {
            importStatus = "Starting fresh."
            importProgress = 1.0
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard token == importStartedToken else { return }
                advanceToWelcome()
            }
            return
        }
        guard selectedBrowser.source != nil else {
            importPhase = .safariNotice
            return
        }

        importProgress = 0.05
        importStatus = "Connecting to profile..."

        Task {
            // 1. Locate the data and scan it: the browser's own folder when
            // it opens directly, otherwise a remembered or freshly granted
            // folder. One scan — its preview feeds the import below.
            importStatus = "Reading bookmarks & history..."
            importProgress = 0.30
            let scan = await resolveImportScan()
            guard token == importStartedToken else { return }
            switch scan {
            case .cancelled:
                // The user dismissed the panel; the step explains and waits.
                importPhase = .needsFolder
                return
            case .failed(let reason):
                importPhase = .failed(reason)
                return
            case .ready(let folder, let preview):
                // 2. Import what the checklist asked for — real counts only.
                importStatus = "Moving it into Lean..."
                importProgress = 0.65
                var landed: [String] = []
                if importBookmarks, !preview.bookmarks.isEmpty {
                    let res = store.importBrowserData(BrowserImportPreview(bookmarks: preview.bookmarks, history: []))
                    importedBookmarksCount = res.bookmarks
                    if res.bookmarks > 0 { landed.append("\(res.bookmarks) bookmarks") }
                }
                if importHistory, !preview.history.isEmpty {
                    let res = store.importBrowserData(BrowserImportPreview(bookmarks: [], history: preview.history))
                    importedHistoryCount = res.history
                    if res.history > 0 { landed.append("\(res.history) history entries") }
                }
                if importPasswords, let source = selectedBrowser.source, source.hasLoginData {
                    importStatus = "Unlocking saved passwords..."
                    if let passwordLine = await importOnboardingPasswords(at: folder, source: source) {
                        landed.append(passwordLine)
                    } else {
                        landed.append("passwords skipped (quit \(selectedBrowser.name) and allow the keychain prompt, then retry from Settings > Import Data)")
                    }
                }
                guard token == importStartedToken else { return }

                importProgress = 1.0
                if landed.isEmpty {
                    importPhase = .failed("Nothing to bring over — no bookmarks, history, or passwords were found in \(selectedBrowser.name)'s profiles. You can import an export file later in Settings > Import Data.")
                } else {
                    importStatus = "Complete."
                    var summary = "From \(selectedBrowser.name): \(landed.joined(separator: ", "))."
                    if preview.historyIncomplete, importHistory {
                        summary += " History may have gaps — quit \(selectedBrowser.name) and re-import from Settings to fill them."
                    }
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    guard token == importStartedToken else { return }
                    importPhase = .finished(summary: summary)
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard token == importStartedToken else { return }
                    advanceToWelcome()
                }
            }
        }
    }

    private enum ImportScan {
        case ready(folder: URL, preview: BrowserImportPreview)
        case cancelled
        case failed(String)
    }

    /// The folder to read plus its scan: the browser's own data folder when
    /// it opens directly, otherwise a remembered grant, otherwise whatever
    /// the user picks in the panel (remembered for next time — the same
    /// bookmark Settings uses, so granting once covers both).
    ///
    /// A remembered or granted folder that scans empty is forgotten on the
    /// spot: keeping it would trap Try Again in a loop on the same wrong
    /// folder with no way to pick another.
    private func resolveImportScan() async -> ImportScan {
        guard let source = selectedBrowser.source else { return .cancelled }
        let direct = source.userDataDirectory
        if FileManager.default.fileExists(atPath: direct.path),
           let preview = await scanProfiles(at: direct),
           !preview.bookmarks.isEmpty || !preview.history.isEmpty {
            return .ready(folder: direct, preview: preview)
        }
        if let remembered = rememberedImportFolder(for: source) {
            if let preview = await scanProfiles(at: remembered),
               !preview.bookmarks.isEmpty || !preview.history.isEmpty {
                return .ready(folder: remembered, preview: preview)
            }
            forgetImportFolder(for: source)
        }
        guard let granted = await requestImportFolder(for: source) else { return .cancelled }
        guard let preview = await scanProfiles(at: granted) else {
            forgetImportFolder(for: source)
            return .failed("Lean couldn't read anything in \(granted.path). Pick the \(source.title) data folder — usually \(source.grantDirectory.path) — and try again.")
        }
        guard !preview.bookmarks.isEmpty || !preview.history.isEmpty else {
            forgetImportFolder(for: source)
            return .failed("\(granted.path) has no \(source.title) profiles in it — no bookmarks or history to bring over.")
        }
        return .ready(folder: granted, preview: preview)
    }

    private func scanProfiles(at folder: URL) async -> BrowserImportPreview? {
        let source = selectedBrowser.source
        return await Task.detached(priority: .userInitiated) {
            let didAccess = folder.startAccessingSecurityScopedResource()
            defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
            return try? BrowserDataImporter.readProfiles(at: folder, source: source)
        }.value
    }

    private func rememberedImportFolder(for source: BrowserImportSource) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: source.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path) else {
            UserDefaults.standard.removeObject(forKey: source.bookmarkKey)
            return nil
        }
        return url
    }

    private func forgetImportFolder(for source: BrowserImportSource) {
        UserDefaults.standard.removeObject(forKey: source.bookmarkKey)
    }

    @MainActor
    private func requestImportFolder(for source: BrowserImportSource) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Allow access to \(source.title) data"
        panel.message = "Select the \(source.title) data folder so Lean can import your bookmarks, history, and passwords. Profiles are found automatically. Usually \(source.grantDirectory.path) — press ⌘⇧G and paste that in, since Library stays hidden."
        panel.prompt = "Allow Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = source.grantDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: source.bookmarkKey)
        }
        return url
    }

    /// Passwords during onboarding. Returns a summary line for the finished
    /// card, or nil when there was nothing (or consent) to report — the
    /// failure already names the next step, so a denial stays quiet here and
    /// the CSV route in Settings remains.
    private func importOnboardingPasswords(at folder: URL, source: BrowserImportSource) async -> String? {
        do {
            let credentials = try await Task.detached(priority: .userInitiated) {
                let didAccess = folder.startAccessingSecurityScopedResource()
                defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
                return try BrowserDataImporter.readPasswords(at: folder, source: source)
            }.value
            guard !credentials.isEmpty else { return nil }
            let saved = BrowserDataImporter.saveCredentials(credentials)
            guard saved.saved > 0 else { return nil }
            return "\(saved.saved) passwords"
        } catch {
            return nil
        }
    }

    // MARK: - Step 6: Welcome (Uses Authentic Lean App Icon)
    private var welcomeStepView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Authentic Lean App Icon
            BrowserIconProvider.image(for: "lean")
                .frame(width: 76, height: 76)
                .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.15), radius: 16, x: 0, y: 8)

            VStack(spacing: 8) {
                Text("Welcome to Lean.")
                    .font(store.headingFont(size: 26))
                    .foregroundColor(primaryText)

                Text("Fast, weightless, and built for deep focus.")
                    .font(store.bodyFont(size: 13.5))
                    .foregroundColor(secondaryText)
            }

            // 5 Minimalist Keyboard Shortcut Badges
            HStack(spacing: 12) {
                shortcutBadge(key: "⌘ T", label: "New Tab")
                shortcutBadge(key: "⌘ ⌥ S", label: "Split View")
                shortcutBadge(key: "⇧ ⌘ Z", label: "Zen Mode")
                shortcutBadge(key: "⌘ P", label: "Pin Tab")
                shortcutBadge(key: "⌘ ,", label: "Settings")
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func shortcutBadge(key: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(cardBorder)
                )

            Text(label)
                .font(store.bodyFont(size: 10))
                .foregroundColor(secondaryText)
        }
        .frame(width: 76)
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack {
            if currentStep != .story && currentStep != .importing && currentStep != .welcome {
                Button {
                    stepBack()
                } label: {
                    HStack(spacing: 4) {
                        Text("←")
                            .font(.system(size: 11, weight: .regular))
                        Text("Back")
                            .font(store.bodyFont(size: 12))
                    }
                    .foregroundColor(secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentStep != .importing && currentStep != .welcome {
                Text("Press ↵ to continue")
                    .font(store.bodyFont(size: 10.5))
                    .foregroundColor(tertiaryText)
            }

            Spacer()

            if currentStep == .welcome {
                Button {
                    store.completeOnboarding()
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Browsing")
                            .font(store.headingFont(size: 13))
                        Text("↵")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(primaryText)
                    )
                }
                .buttonStyle(.plain)
            } else if currentStep != .importing {
                Button {
                    advanceStep()
                } label: {
                    HStack(spacing: 6) {
                        Text(currentStep == .checklist ? "Begin Import" : "Continue")
                            .font(store.headingFont(size: 12.5))
                        Text("→")
                            .font(.system(size: 11, weight: .regular))
                    }
                    .foregroundColor(isDark ? .black : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(primaryText)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: - Navigation Helpers
    private func advanceStep() {
        navigationDirection = 1
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                // Entering the importing step starts a fresh run; re-entering
                // it (Back, then Continue) must not resume a stale one.
                if next == .importing {
                    importPhase = .working
                    importProgress = 0.05
                    importStatus = "Connecting to profile..."
                    importedBookmarksCount = 0
                    importedHistoryCount = 0
                    importStartedToken = UUID()
                }
                currentStep = next
            } else {
                store.completeOnboarding()
            }
        }
    }

    private func stepBack() {
        navigationDirection = -1
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                currentStep = prev
            }
        }
    }

    private func navigateToStep(_ target: OnboardingStep) {
        guard target.rawValue < currentStep.rawValue else { return }
        navigationDirection = -1
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            currentStep = target
        }
    }

    // MARK: - Keyboard Monitor
    private func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Return / Enter -> advance
            if event.keyCode == 36 {
                if currentStep == .welcome {
                    store.completeOnboarding()
                    return nil
                } else if currentStep != .importing {
                    advanceStep()
                    return nil
                }
            }
            // Escape -> skip
            if event.keyCode == 53 {
                store.completeOnboarding()
                return nil
            }
            // Delete / Backspace or Cmd+Left -> go back
            if event.keyCode == 51 || (event.keyCode == 123 && event.modifierFlags.contains(.command)) {
                if currentStep != .story && currentStep != .importing && currentStep != .welcome {
                    stepBack()
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
