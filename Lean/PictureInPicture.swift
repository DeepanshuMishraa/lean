// Adapted from Search by Office Commun, licensed under the MIT License.
// Copyright (c) 2026 Office Commun. See the Search repository LICENSE.
import AppKit
import WebKit

// A video that keeps playing after you have gone somewhere else, in a small
// window that stays above everything — other tabs, and other apps.
//
// WebKit will not hand a video to the system's picture-in-picture without a
// real click on the page, and nothing the app does counts as one. Chromium is
// looser, which is why this works elsewhere and refused here.
//
// So the engine is not asked. The page itself is moved: everything but the
// video is made invisible, the video is stretched to fill the viewport, and the
// whole web view is lifted out of the window and into a small floating one. The
// video never stops, because it is the same page it always was — it has only
// changed windows.

@MainActor
final class PictureInPicture {
    private var panel: NSPanel?
    private var controls: Controls?
    private weak var page: NSView?

    /// Asked to go away. The browser does the bookkeeping and calls back into
    /// `drop` — there is one way this window closes, and it is not this class
    /// quietly tidying up behind everyone's back. Two paths to closing is how
    /// it stayed on screen after the page had already gone home.
    var onClose: (() -> Void)?
    /// Bring the window forward and go to the tab it came from.
    var onReturn: (() -> Void)?
    /// Stop or start the video. Answers with whether it is playing now.
    var onPlayPause: ((@escaping (Bool) -> Void) -> Void)?
    /// Step over the bit you missed, or back to it.
    var onSkip: ((Double) -> Void)?
    /// Seek to a specific fraction of duration [0..1].
    var onSeek: ((Double) -> Void)?
    /// Asked every half second while the window is up: progress, playing state, current time, duration.
    var onProgress: ((@escaping (Double, Bool, Double, Double) -> Void) -> Void)?

    private var ticker: Timer?

    var showing: Bool { panel != nil }

    func lift(_ page: NSView, aspectRatio: CGFloat, title: String? = nil, url: URL? = nil, favicon: NSImage? = nil) {
        guard panel == nil else { return }
        self.page = page

        let size = NSSize(width: 440, height: 440 / max(0.5, aspectRatio))
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let spot = NSRect(
            x: screen.maxX - size.width - 24,
            y: screen.minY + 24,
            width: size.width,
            height: size.height
        )

        let panel = PictureInPicturePanel(
            contentRect: spot,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above every ordinary window, this app's and everyone else's, and
        // present on whichever desktop you happen to be looking at.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        // Appear instantly: the default fade makes the widget feel slow.
        panel.animationBehavior = .none
        panel.aspectRatio = NSSize(width: aspectRatio, height: 1)
        panel.minSize = NSSize(width: 260, height: 146)
        panel.setFrameAutosaveName("LeanPictureInPicture")
        if !panel.setFrameUsingName("LeanPictureInPicture") {
            panel.setFrame(spot, display: false)
        }

        let ground = NSView(frame: NSRect(origin: .zero, size: size))
        ground.wantsLayer = true
        ground.layer?.backgroundColor = NSColor.black.cgColor
        ground.layer?.cornerRadius = 16
        ground.layer?.cornerCurve = .continuous
        ground.layer?.masksToBounds = true
        ground.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        ground.layer?.borderWidth = 0.75

        // WebKit puts its own pinch recogniser on a web view, and a gesture
        // recogniser is consulted before the responder chain is. With it left
        // on, every pinch aimed at this window went into zooming the page
        // inside it instead of sizing the window. It comes back on landing.
        (page as? WKWebView)?.allowsMagnification = false

        // Reparenting the live web view forces a full relayout; suppress
        // implicit animations so the lift doesn't stutter. No synchronous
        // layout pass here: forcing one on a heavy page (YouTube) blocks
        // the tab switch for hundreds of milliseconds. The autoresizing
        // mask plus the next layout pass settles it without the hitch.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        page.removeFromSuperview()
        page.frame = ground.bounds
        page.autoresizingMask = [.width, .height]
        ground.addSubview(page)
        CATransaction.commit()

        let controls = Controls(frame: ground.bounds)
        controls.autoresizingMask = [.width, .height]
        controls.updateMetadata(title: title, url: url, favicon: favicon)
        controls.onClose = { [weak self] in self?.onClose?() }
        controls.onReturn = { [weak self] in self?.onReturn?() }
        controls.onPlayPause = { [weak self] in
            self?.onPlayPause? { playing in
                self?.controls?.playing = playing
            }
        }
        controls.onSkip = { [weak self] seconds in self?.onSkip?(seconds) }
        controls.onSeek = { [weak self] fraction in self?.onSeek?(fraction) }
        ground.addSubview(controls)
        self.controls = controls

        panel.contentView = ground
        // Start invisible: reparenting kicks a full relayout at the new
        // size, and the first composites mid-churn flash page chrome
        // (YouTube's logo included). reveal() fades in once the isolated
        // layout has settled, so the window opens onto video, not flicker.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                // A window that no longer holds the page has nothing to show
                // and no reason to exist. Something else took the page back —
                // and rather than hunt every path that could, this makes it
                // impossible for the empty black rectangle to outlive it by
                // more than half a second.
                if self.page?.superview !== ground {
                    self.onClose?()
                    return
                }

                self.onProgress? { through, playing, currentTime, duration in
                    self.controls?.updateProgress(
                        through: through,
                        playing: playing,
                        currentTime: currentTime,
                        duration: duration
                    )
                }
            }
        }
    }

    /// Fade in after the isolated layout has settled (see Isolate.settled).
    /// A no-op once visible or after the window is gone, so a late probe
    /// answer or the fallback timer can both call it safely.
    func reveal() {
        guard let panel, panel.alphaValue < 1 else { return }
        panel.animator().alphaValue = 1
    }

    /// Puts the page down and closes. Whoever owns the page takes it back on
    /// their next layout.
    func drop() {
        guard let panel else { return }
        ticker?.invalidate()
        ticker = nil
        (page as? WKWebView)?.allowsMagnification = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        page?.removeFromSuperview()
        CATransaction.commit()
        page = nil
        controls = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    // MARK: - Glassmorphic Subviews

    /// Tactile frosted glass button with subtle hairline border and hover feedback.
    private final class PipGlassButton: NSButton {
        var isDestructiveHover = false
        var isHero = false
        var isGhost = false
        private var isHovered = false {
            didSet { updateAppearance() }
        }
        private var trackingArea: NSTrackingArea?

        override init(frame: NSRect) {
            super.init(frame: frame)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            wantsLayer = true
            isBordered = false
            bezelStyle = .regularSquare
            imagePosition = .imageOnly
            layer?.cornerCurve = .continuous
            layer?.borderWidth = 0.75
            updateAppearance()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            self.trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            super.mouseEntered(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            super.mouseExited(with: event)
        }

        override var isHighlighted: Bool {
            didSet { updateAppearance() }
        }

        private func updateAppearance() {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            layer?.cornerRadius = min(bounds.width, bounds.height) / 2

            if isHighlighted {
                layer?.backgroundColor = NSColor(white: 0.35, alpha: 0.88).cgColor
                layer?.borderColor = NSColor(white: 1.0, alpha: 0.38).cgColor
            } else if isHovered {
                if isDestructiveHover {
                    layer?.backgroundColor = NSColor(red: 0.92, green: 0.24, blue: 0.24, alpha: 0.75).cgColor
                    layer?.borderColor = NSColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 0.55).cgColor
                } else if isHero {
                    layer?.backgroundColor = NSColor(white: 0.28, alpha: 0.88).cgColor
                    layer?.borderColor = NSColor(white: 1.0, alpha: 0.40).cgColor
                } else {
                    layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.82).cgColor
                    layer?.borderColor = NSColor(white: 1.0, alpha: 0.30).cgColor
                }
            } else {
                if isHero {
                    layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.68).cgColor
                    layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
                } else if isGhost {
                    layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.45).cgColor
                    layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
                } else {
                    layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.58).cgColor
                    layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
                }
            }
            CATransaction.commit()
        }

        override func layout() {
            super.layout()
            layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        }
    }

    /// Top-left frosted glass pill holding close button and site/YouTube icon.
    private final class PipTopBadge: NSView {
        let closeButton = PipGlassButton()
        private let separator = NSView()
        private let iconView = NSImageView()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.cornerRadius = 13
            layer?.cornerCurve = .continuous
            layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.60).cgColor
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            layer?.borderWidth = 0.75

            closeButton.isDestructiveHover = true
            closeButton.image = Controls.glyph("xmark", 8.5, weight: .bold)
            closeButton.toolTip = "Close (Esc)"
            closeButton.frame = NSRect(x: 3, y: 3, width: 20, height: 20)
            addSubview(closeButton)

            separator.wantsLayer = true
            separator.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.16).cgColor
            separator.frame = NSRect(x: 26, y: 7, width: 0.75, height: 12)
            addSubview(separator)

            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.frame = NSRect(x: 31, y: 6, width: 16, height: 14)
            addSubview(iconView)
        }

        required init?(coder: NSCoder) { fatalError() }

        func setIcon(_ image: NSImage, toolTipText: String?) {
            iconView.image = image
            toolTip = toolTipText
        }

        var badgeWidth: CGFloat { 54 }
    }

    /// Center media dock cluster with rewind, hero play/pause, and forward.
    private final class PipCenterCluster: NSView {
        let rewindButton = PipGlassButton()
        let playPauseButton = PipGlassButton()
        let forwardButton = PipGlassButton()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true

            playPauseButton.isHero = true
            rewindButton.isGhost = true
            forwardButton.isGhost = true

            rewindButton.image = Controls.glyph("gobackward.15", 11.5)
            playPauseButton.image = Controls.glyph("pause.fill", 16, weight: .bold)
            forwardButton.image = Controls.glyph("goforward.15", 11.5)

            rewindButton.toolTip = "Rewind 15s (←)"
            playPauseButton.toolTip = "Play / Pause (Space)"
            forwardButton.toolTip = "Forward 15s (→)"

            addSubview(rewindButton)
            addSubview(playPauseButton)
            addSubview(forwardButton)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            rewindButton.frame = NSRect(x: 0, y: 6, width: 28, height: 28)
            playPauseButton.frame = NSRect(x: 38, y: 0, width: 40, height: 40)
            forwardButton.frame = NSRect(x: 88, y: 6, width: 28, height: 28)
        }
    }

    /// Interactive track that expands on hover with glowing thumb and scrubbing.
    private final class PipScrubberTrack: NSView {
        var progress: Double = 0 {
            didSet { needsDisplay = true }
        }
        var isDragging = false
        var onSeek: ((Double) -> Void)?

        private var isHovered = false {
            didSet { needsDisplay = true }
        }
        private var trackingArea: NSTrackingArea?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            self.trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
        }

        override func mouseDown(with event: NSEvent) {
            isDragging = true
            seek(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging else { return }
            seek(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            guard isDragging else { return }
            isDragging = false
            seek(with: event)
        }

        private func seek(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            guard bounds.width > 0 else { return }
            let p = max(0.0, min(1.0, Double(local.x / bounds.width)))
            progress = p
            onSeek?(p)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard bounds.width > 0 else { return }

            let barHeight: CGFloat = (isHovered || isDragging) ? 4.0 : 2.5
            let barY = (bounds.height - barHeight) / 2
            let barRect = NSRect(x: 0, y: barY, width: bounds.width, height: barHeight)

            // Background track
            let bgPath = NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            NSColor(white: 1.0, alpha: 0.18).setFill()
            bgPath.fill()

            // Filled progress
            let fillW = max(barHeight, bounds.width * CGFloat(progress))
            let fillRect = NSRect(x: 0, y: barY, width: fillW, height: barHeight)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            NSColor(white: 0.95, alpha: 1.0).setFill()
            fillPath.fill()

            // Scrubber thumb
            let thumbDiameter: CGFloat = (isHovered || isDragging) ? 9.5 : 7.5
            let thumbX = min(max(0, bounds.width * CGFloat(progress) - thumbDiameter / 2), bounds.width - thumbDiameter)
            let thumbY = (bounds.height - thumbDiameter) / 2
            let thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbDiameter, height: thumbDiameter)

            let thumbPath = NSBezierPath(ovalIn: thumbRect)
            if isHovered || isDragging {
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
                shadow.shadowBlurRadius = 3
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.set()
                NSColor.white.setFill()
                thumbPath.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor(white: 1.0, alpha: 0.9).setFill()
                thumbPath.fill()
            }
        }
    }

    /// Bottom scrubber bar with real-time timestamps.
    private final class PipScrubber: NSView {
        let timeCurrentLabel = NSTextField(labelWithString: "00:00")
        let trackView = PipScrubberTrack()
        let timeTotalLabel = NSTextField(labelWithString: "00:00")

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true

            let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
            timeCurrentLabel.font = font
            timeCurrentLabel.textColor = NSColor(white: 0.75, alpha: 0.9)
            timeCurrentLabel.alignment = .left
            timeCurrentLabel.isBezeled = false
            timeCurrentLabel.drawsBackground = false
            timeCurrentLabel.isEditable = false
            timeCurrentLabel.isSelectable = false
            addSubview(timeCurrentLabel)

            timeTotalLabel.font = font
            timeTotalLabel.textColor = NSColor(white: 0.50, alpha: 0.9)
            timeTotalLabel.alignment = .right
            timeTotalLabel.isBezeled = false
            timeTotalLabel.drawsBackground = false
            timeTotalLabel.isEditable = false
            timeTotalLabel.isSelectable = false
            addSubview(timeTotalLabel)

            addSubview(trackView)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            let labelW: CGFloat = 32
            timeCurrentLabel.frame = NSRect(x: 0, y: 0, width: labelW, height: 16)
            timeTotalLabel.frame = NSRect(x: bounds.width - labelW, y: 0, width: labelW, height: 16)
            trackView.frame = NSRect(
                x: labelW + 6,
                y: 0,
                width: max(10, bounds.width - (labelW * 2 + 12)),
                height: bounds.height
            )
        }

        func update(progress: Double, currentTime: Double, duration: Double) {
            trackView.progress = progress
            timeCurrentLabel.stringValue = Controls.formatTime(currentTime)
            timeTotalLabel.stringValue = duration > 0 ? Controls.formatTime(duration) : "--:--"
        }
    }

    /// Subtle resize indicator in the bottom-right corner.
    private final class PipResizeGrip: NSView {
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.28).cgColor)
            let dots: [CGPoint] = [
                CGPoint(x: bounds.maxX - 4, y: bounds.minY + 4),
                CGPoint(x: bounds.maxX - 8, y: bounds.minY + 4),
                CGPoint(x: bounds.maxX - 4, y: bounds.minY + 8),
                CGPoint(x: bounds.maxX - 12, y: bounds.minY + 4),
                CGPoint(x: bounds.maxX - 8, y: bounds.minY + 8),
                CGPoint(x: bounds.maxX - 4, y: bounds.minY + 12)
            ]
            for dot in dots {
                ctx.fillEllipse(in: CGRect(x: dot.x - 1, y: dot.y - 1, width: 2, height: 2))
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    /// The interactive overlay for the Picture-in-Picture window.
    private final class Controls: NSView {
        var onClose: (() -> Void)?
        var onReturn: (() -> Void)?
        var onPlayPause: (() -> Void)?
        var onSkip: ((Double) -> Void)?
        var onSeek: ((Double) -> Void)?

        var playing = true {
            didSet {
                centerCluster.playPauseButton.image = Controls.glyph(playing ? "pause.fill" : "play.fill", 16, weight: .bold)
                if !playing {
                    fade(to: 1)
                    inactivityTimer?.invalidate()
                    inactivityTimer = nil
                } else {
                    resetInactivityTimer()
                }
            }
        }

        var progress: Double = 0

        let topBadge = PipTopBadge()
        let returnButton = PipGlassButton()
        let centerCluster = PipCenterCluster()
        let scrubber = PipScrubber()
        let resizeGrip = PipResizeGrip()

        private var near = false
        private var inactivityTimer: Timer?

        override var mouseDownCanMoveWindow: Bool { true }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.cornerRadius = 16
            layer?.cornerCurve = .continuous
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
            layer?.borderWidth = 0.75

            returnButton.image = Controls.glyph("arrow.up.forward", 11.5, weight: .semibold)
            returnButton.toolTip = "Return to tab (Return)"
            returnButton.target = self
            returnButton.action = #selector(pressedReturn)

            topBadge.closeButton.target = self
            topBadge.closeButton.action = #selector(pressedClose)

            centerCluster.rewindButton.target = self
            centerCluster.rewindButton.action = #selector(pressedRewind)

            centerCluster.playPauseButton.target = self
            centerCluster.playPauseButton.action = #selector(pressedPause)

            centerCluster.forwardButton.target = self
            centerCluster.forwardButton.action = #selector(pressedForward)

            scrubber.trackView.onSeek = { [weak self] p in
                self?.onSeek?(p)
                self?.resetInactivityTimer()
            }

            addSubview(topBadge)
            addSubview(returnButton)
            addSubview(centerCluster)
            addSubview(scrubber)
            addSubview(resizeGrip)

            [topBadge, returnButton, centerCluster, scrubber, resizeGrip].forEach { $0.alphaValue = 0 }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        static func siteIcon(for url: URL?, favicon: NSImage?) -> NSImage {
            let host = url?.host()?.lowercased() ?? ""
            if host.contains("youtube") || host.contains("youtu.be") {
                return youtubeBadge()
            }
            if let favicon {
                return favicon
            }
            if let cached = FaviconService.shared.cachedFavicon(for: url) {
                return cached
            }
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            return NSImage(systemSymbolName: "play.tv.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) ?? NSImage()
        }

        static func youtubeBadge() -> NSImage {
            let width: CGFloat = 16
            let height: CGFloat = 11.5
            let img = NSImage(size: NSSize(width: width, height: height))
            img.lockFocus()
            let rect = NSRect(x: 0, y: 0, width: width, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            NSColor(red: 255/255, green: 0, blue: 0, alpha: 1.0).setFill()
            path.fill()
            let tri = NSBezierPath()
            let cx = width / 2 + 0.4
            let cy = height / 2
            let th: CGFloat = 3.0
            let tw: CGFloat = 3.2
            tri.move(to: NSPoint(x: cx - tw/2, y: cy + th))
            tri.line(to: NSPoint(x: cx + tw/2 + 0.5, y: cy))
            tri.line(to: NSPoint(x: cx - tw/2, y: cy - th))
            tri.close()
            NSColor.white.setFill()
            tri.fill()
            img.unlockFocus()
            return img
        }

        func updateMetadata(title: String?, url: URL?, favicon: NSImage? = nil) {
            let icon = Controls.siteIcon(for: url, favicon: favicon)
            let tip = title ?? url?.host() ?? "Lean"
            topBadge.setIcon(icon, toolTipText: tip)

            if favicon == nil, let url {
                FaviconService.shared.loadFavicon(for: url) { [weak self] loaded in
                    guard let self, let loaded else { return }
                    let host = url.host()?.lowercased() ?? ""
                    if !host.contains("youtube") && !host.contains("youtu.be") {
                        self.topBadge.setIcon(loaded, toolTipText: tip)
                    }
                }
            }
            needsLayout = true
        }

        func updateProgress(through: Double, playing: Bool, currentTime: Double, duration: Double) {
            self.progress = through
            self.playing = playing
            if !scrubber.trackView.isDragging {
                scrubber.update(progress: through, currentTime: currentTime, duration: duration)
            }
        }

        static func glyph(_ name: String, _ size: CGFloat, weight: NSFont.Weight = .medium) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            let look = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
                .applying(.init(paletteColors: [.white]))
            return image?.withSymbolConfiguration(look)
        }

        static func formatTime(_ seconds: Double) -> String {
            guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00" }
            let total = Int(seconds)
            let s = total % 60
            let m = (total / 60) % 60
            let h = total / 3600
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            } else {
                return String(format: "%02d:%02d", m, s)
            }
        }

        override func layout() {
            super.layout()

            let topY = bounds.height - 36
            topBadge.frame = NSRect(x: 12, y: topY, width: topBadge.badgeWidth, height: 26)
            returnButton.frame = NSRect(x: bounds.width - 38, y: topY, width: 26, height: 26)

            let clusterW: CGFloat = 116
            let clusterH: CGFloat = 40
            centerCluster.frame = NSRect(
                x: (bounds.width - clusterW) / 2,
                y: (bounds.height - clusterH) / 2,
                width: clusterW,
                height: clusterH
            )

            // Leave 34pt clear on the right edge so the scrubber never overlaps the corner resize zone
            scrubber.frame = NSRect(
                x: 12,
                y: 8,
                width: max(80, bounds.width - 24 - 34),
                height: 16
            )

            resizeGrip.frame = NSRect(
                x: bounds.maxX - 16,
                y: bounds.minY + 4,
                width: 12,
                height: 12
            )
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) {
            fade(to: 1)
            resetInactivityTimer()
        }

        override func mouseMoved(with event: NSEvent) {
            if !near {
                fade(to: 1)
            }
            resetInactivityTimer()
        }

        override func mouseExited(with event: NSEvent) {
            guard let window else { return }
            let mouse = window.mouseLocationOutsideOfEventStream
            let local = convert(mouse, from: nil)
            if bounds.contains(local) { return }

            if !scrubber.trackView.isDragging {
                fade(to: 0)
                inactivityTimer?.invalidate()
                inactivityTimer = nil
            }
        }

        private func resetInactivityTimer() {
            inactivityTimer?.invalidate()
            inactivityTimer = nil
            guard playing, !scrubber.trackView.isDragging else { return }
            inactivityTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.playing, !self.scrubber.trackView.isDragging else { return }
                    self.fade(to: 0)
                }
            }
        }

        private func fade(to value: CGFloat) {
            near = value > 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                topBadge.animator().alphaValue = value
                returnButton.animator().alphaValue = value
                centerCluster.animator().alphaValue = value
                scrubber.animator().alphaValue = value
                resizeGrip.animator().alphaValue = value
            }
        }

        /// Everything reaches this layer.
        ///
        /// isMovableByWindowBackground never worked here: the window's whole
        /// background is a web view, and a web view swallows every drag before
        /// the window sees it. So every gesture is taken here, above it.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let inside = convert(point, from: superview)

            // Generous corner resize zone: always prioritize resizing over controls
            if atCorner(inside) {
                return self
            }

            if near {
                let closePoint = topBadge.closeButton.convert(inside, from: self)
                if topBadge.closeButton.bounds.contains(closePoint) {
                    return topBadge.closeButton
                }

                let returnPoint = returnButton.convert(inside, from: self)
                if returnButton.bounds.contains(returnPoint) {
                    return returnButton
                }

                let rewPoint = centerCluster.rewindButton.convert(inside, from: self)
                if centerCluster.rewindButton.bounds.contains(rewPoint) {
                    return centerCluster.rewindButton
                }

                let playPoint = centerCluster.playPauseButton.convert(inside, from: self)
                if centerCluster.playPauseButton.bounds.contains(playPoint) {
                    return centerCluster.playPauseButton
                }

                let fwdPoint = centerCluster.forwardButton.convert(inside, from: self)
                if centerCluster.forwardButton.bounds.contains(fwdPoint) {
                    return centerCluster.forwardButton
                }

                let trackPoint = scrubber.trackView.convert(inside, from: self)
                let trackHitRect = scrubber.trackView.bounds.insetBy(dx: 0, dy: -6)
                if trackHitRect.contains(trackPoint) {
                    return scrubber.trackView
                }
            }
            return self
        }

        // MARK: - Moving and Sizing

        private var grab = NSPoint.zero
        private var origin = NSRect.zero
        private var stretching = false

        private func atCorner(_ point: NSPoint) -> Bool {
            point.x > bounds.maxX - 32 && point.y < bounds.minY + 32
        }

        override func resetCursorRects() {
            addCursorRect(
                NSRect(x: bounds.maxX - 32, y: bounds.minY, width: 32, height: 32),
                cursor: .crosshair
            )
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            window.makeFirstResponder(self)

            let loc = convert(event.locationInWindow, from: nil)
            if event.clickCount == 2 && !atCorner(loc) {
                togglePlayPause()
                return
            }

            grab = NSEvent.mouseLocation
            origin = window.frame

            if atCorner(loc) {
                stretching = true
                return
            }

            stretching = false
            window.performDrag(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let dx = now.x - grab.x
            let dy = now.y - grab.y

            if stretching {
                // Expanding when dragging right or down; shrinking when dragging left or up
                let delta = abs(dx) >= abs(dy) ? dx : -dy
                resize(to: origin.width + delta, from: origin)
            } else {
                // Fallback movement if performDrag didn't capture the gesture
                window.setFrameOrigin(NSPoint(x: origin.minX + dx, y: origin.minY + dy))
            }
        }

        /// Two fingers on the trackpad move the window. There is nothing to
        /// scroll here — the window holds one picture — so the gesture is free
        /// to mean the thing you actually want it to mean.
        ///
        /// And the pointer travels with it. Moving the window alone leaves the
        /// cursor behind: it drifts towards the edge, falls out, and the window
        /// stops answering mid-gesture. Carrying it keeps it at the same place
        /// in the frame, so the window can be pushed as far as the screen goes.
        override func scrollWheel(with event: NSEvent) {
            guard let window else { return }
            // Only while fingers are actually down. Letting the glide continue
            // would fling the pointer across the screen after them.
            guard event.momentumPhase == [] else { return }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard dx != 0 || dy != 0 else { return }

            let spot = window.frame.origin
            window.setFrameOrigin(NSPoint(x: spot.x + dx, y: spot.y - dy))

            // Screen coordinates run up from the bottom, the cursor's run down
            // from the top of the first display.
            guard let ground = NSScreen.screens.first else { return }
            let mouse = NSEvent.mouseLocation
            CGWarpMouseCursorPosition(
                CGPoint(
                    x: mouse.x + dx,
                    y: ground.frame.height - (mouse.y - dy)
                )
            )
            // Without this the pointer and the physical trackpad stay parted
            // for a moment, and the next flick arrives from the wrong place.
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        /// A pinch sizes it about the pointer: whatever is under your fingers
        /// stays under your fingers, and the rest grows away from it. Sizing
        /// about the centre instead makes the picture slide sideways under a
        /// hand that never moved, which is what felt wrong.
        private var pinching: CGFloat = 0

        override func magnify(with event: NSEvent) {
            guard let window else { return }
            if event.phase == .began { pinching = 0 }
            pinching += event.magnification

            // Every event would mean a window resize, a web view relayout and a
            // video re-fit sixty times a second, which is the stutter. Moving
            // in steps of a fiftieth is below what an eye reads as a jump and
            // an order of magnitude less work.
            guard abs(pinching) > 0.02 else { return }
            let by = pinching
            pinching = 0
            resize(
                to: window.frame.width * (1 + by),
                from: window.frame,
                around: NSEvent.mouseLocation
            )
        }

        private func resize(to width: CGFloat, from was: NSRect, around anchor: NSPoint? = nil) {
            guard let window, was.width > 0 else { return }
            let limit = NSScreen.main?.visibleFrame.width ?? 1600
            // Keeps the shape: a video window that can be squashed is a video
            // window showing bars.
            let wide = min(max(window.minSize.width, width), limit * 0.85)
            let tall = wide * was.height / was.width

            let spot: NSPoint
            if let anchor {
                // Where the pointer sits within the window, as a fraction, kept
                // at the same fraction of the new one.
                let across = (anchor.x - was.minX) / was.width
                let up = (anchor.y - was.minY) / was.height
                spot = NSPoint(x: anchor.x - across * wide, y: anchor.y - up * tall)
            } else {
                spot = NSPoint(x: was.minX, y: was.maxY - tall)
            }
            // Not display: true — asking for an immediate redraw on every step
            // is what makes a live resize stutter. The next frame is soon
            // enough.
            window.setFrame(
                NSRect(x: spot.x, y: spot.y, width: wide, height: tall),
                display: false
            )
        }

        // MARK: - First Responder and Keyboard

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 49: // Space
                togglePlayPause()
            case 123: // Left Arrow
                pressedRewind()
            case 124: // Right Arrow
                pressedForward()
            case 53: // Esc
                pressedClose()
            case 36: // Return
                pressedReturn()
            default:
                super.keyDown(with: event)
            }
        }

        private func togglePlayPause() {
            playing.toggle()
            onPlayPause?()
        }

        @objc private func pressedClose() { onClose?() }
        @objc private func pressedReturn() { onReturn?() }
        @objc private func pressedRewind() { onSkip?(-15) }
        @objc private func pressedForward() { onSkip?(15) }
        @objc private func pressedPause() { togglePlayPause() }
    }
}

/// Sites with a player worth following into the little window.
///
/// Anywhere else, a playing video is as likely to be a background as a film,
/// and the difference isn't something a script can tell from the outside. So
/// the list is of places people go to watch, and the shortcut covers the rest.
enum Players {
    /// A host suffix, and for a few shops that also stream, the path that
    /// separates the film from the product page.
    private static let known: [(host: String, path: String?)] = [
        ("youtube.com", nil), ("youtu.be", nil), ("netflix.com", nil),
        ("primevideo.com", nil), ("amazon.com", "/gp/video"), ("amazon.fr", "/gp/video"),
        ("amazon.co.uk", "/gp/video"), ("amazon.de", "/gp/video"),
        ("disneyplus.com", nil), ("tv.apple.com", nil), ("twitch.tv", nil),
        ("vimeo.com", nil), ("dailymotion.com", nil), ("max.com", nil), ("hbomax.com", nil),
        ("canalplus.com", nil), ("mycanal.fr", nil), ("arte.tv", nil), ("france.tv", nil),
        ("tf1.fr", nil), ("6play.fr", nil), ("crunchyroll.com", nil), ("plex.tv", nil),
        ("peacocktv.com", nil), ("hulu.com", nil), ("paramountplus.com", nil),
        ("molotov.tv", nil), ("ocs.fr", nil), ("mubi.com", nil), ("criterionchannel.com", nil),
        ("ted.com", nil), ("nebula.tv", nil), ("curiositystream.com", nil),
    ]

    static func knows(_ url: URL?) -> Bool {
        guard let url, let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        return known.contains { entry in
            guard host == entry.host || host.hasSuffix("." + entry.host) else { return false }
            guard let needle = entry.path else { return true }
            return path.hasPrefix(needle)
        }
    }
}

/// A panel that takes key status without bringing the whole app forward.
///
/// Borderless windows refuse to become key by default, and a window that never
/// becomes key is a window the system stops routing gestures to.
private final class PictureInPicturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum Isolate {
    /// Everything but the video, out of the way. Visibility is inherited, so
    /// hiding the body and turning it back on for the video alone leaves the
    /// player's own machinery running untouched — which is what keeps the
    /// stream alive where cutting the DOM about would kill it.
    ///
    /// Never moves DOM nodes: the video stays where its player put it, so a
    /// React re-render, quality change, or ad break cannot orphan it, and
    /// landing needs no saved parent to restore (a stale parent was what
    /// left the page blank on return). Mirrors Search's Float.Isolate.
    static let on = """
    (function () {
      var videos = document.querySelectorAll('video');
      var best = null, area = 0;
      for (var i = 0; i < videos.length; i++) {
        var v = videos[i];
        if (v.paused || v.ended || v.readyState < 2) continue;
        var box = v.getBoundingClientRect();
        if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
      }
      if (!best) return 'none';

      best.setAttribute('data-lean-picture-in-picture', '');
      var sheet = document.getElementById('lean-picture-in-picture');
      if (!sheet) {
        sheet = document.createElement('style');
        sheet.id = 'lean-picture-in-picture';
        (document.head || document.documentElement).appendChild(sheet);
      }
      sheet.textContent = [
        'html.lean-picture-in-picture-active, html.lean-picture-in-picture-active body {',
        'background:#000 !important; overflow:hidden !important; margin:0 !important}',
        'html.lean-picture-in-picture-active body > * { visibility:hidden !important }',
        'html.lean-picture-in-picture-active [data-lean-picture-in-picture] {',
        'visibility:visible !important; position:fixed !important;',
        'left:0 !important; top:0 !important; right:0 !important; bottom:0 !important;',
        'width:100vw !important; height:100vh !important;',
        'max-width:none !important; max-height:none !important;',
        // Players such as Netflix center the element with a translation.
        // With our top/left at zero, that moves it out of the floating window.
        'transform:none !important;',
        'object-fit:contain !important; object-position:center !important;',
        'z-index:2147483647 !important}',
        // Netflix renders timed text after the video, in a layer of its own
        // beside it or one level up. Keep it above the video without
        // exposing the rest of the player.
        'html.lean-picture-in-picture-active [data-lean-picture-in-picture] ~ .player-timedtext,',
        'html.lean-picture-in-picture-active :has(> [data-lean-picture-in-picture]) > .player-timedtext,',
        'html.lean-picture-in-picture-active :has([data-lean-picture-in-picture]) > .player-timedtext {',
        'visibility:visible !important; z-index:2147483647 !important}',
        // Fixed or not, the video is still cut to the box of any ancestor
        // that clips — YouTube's player does — and in a window this small
        // that box sits partly or wholly off screen, more so on a page that
        // was scrolled. That was the black window.
        'html.lean-picture-in-picture-active body :has([data-lean-picture-in-picture]) {',
        'overflow:visible !important}',
        // The player's own controls would sit under ours, and two sets of
        // buttons on one small window is one set too many.
        'html.lean-picture-in-picture-active [data-lean-picture-in-picture]::-webkit-media-controls {',
        'display:none !important}'
      ].join('');
      document.documentElement.classList.add('lean-picture-in-picture-active');

      // The mark has to be defended.
      //
      // Everything but the marked element is hidden, so the moment a player
      // rebuilds its DOM — and they all do, on a quality change, an ad break,
      // a React re-render — the mark goes with the old element and the window
      // turns pure black while still holding a perfectly live page. That is the
      // black rectangle, and it is not an orphaned window at all.
      //
      // So the mark is put back on whatever is playing now, four times a
      // second, for as long as the page is out.
      clearInterval(window.__leanPictureInPictureWatch);
      window.__leanPictureInPictureWatch = setInterval(function () {
        if (document.querySelector('[data-lean-picture-in-picture]')) return;
        var again = null, most = 0;
        var all = document.querySelectorAll('video');
        for (var j = 0; j < all.length; j++) {
          var one = all[j];
          if (one.paused || one.ended || one.readyState < 2) continue;
          var shape = one.getBoundingClientRect();
          if (shape.width * shape.height >= most) {
            most = shape.width * shape.height;
            again = one;
          }
        }
        if (again) again.setAttribute('data-lean-picture-in-picture', '');
      }, 250);

      return { width: best.videoWidth, height: best.videoHeight };
    })();
    """

    /// Stop or start it, and say which it is now.
    /// Step over the bit you missed, or back to it.
    static func skip(_ seconds: Double) -> String {
        """
        (function () {
          var video = document.querySelector('[data-lean-picture-in-picture]')
            || document.querySelector('video');
          if (!video) return false;
          video.currentTime = Math.max(0, video.currentTime + (\(seconds)));
          return true;
        })();
        """
    }

    /// Seek to a fraction [0..1] of video duration.
    static func seek(_ fraction: Double) -> String {
        """
        (function () {
          var video = document.querySelector('[data-lean-picture-in-picture]')
            || document.querySelector('video');
          if (!video || !video.duration || !isFinite(video.duration)) return false;
          video.currentTime = Math.max(0, Math.min(video.duration, video.duration * (\(fraction))));
          return true;
        })();
        """
    }

    /// True once the isolated layout has survived two frames with the
    /// marked video still in the DOM at a real size — i.e. the resize
    /// churn is over and revealing the window shows video, not flicker.
    /// Returns a Promise, which WebKit resolves before answering.
    static let settled = """
    (function () {
      return new Promise(function (resolve) {
        requestAnimationFrame(function () {
          requestAnimationFrame(function () {
            var el = document.querySelector('[data-lean-picture-in-picture]');
            if (!el) { resolve(false); return; }
            var box = el.getBoundingClientRect();
            resolve(box.width > 2 && box.height > 2);
          });
        });
      });
    })();
    """

    /// How far through, whether it is running, current time, and duration.
    static let where_ = """
    (function () {
      var video = document.querySelector('[data-lean-picture-in-picture]')
        || document.querySelector('video');
      if (!video || !video.duration || !isFinite(video.duration)) return [0, true, 0, 0];
      return [video.currentTime / video.duration, !video.paused, video.currentTime || 0, video.duration || 0];
    })();
    """

    static let toggle = """
    (function () {
      var video = document.querySelector('[data-lean-picture-in-picture]')
        || document.querySelector('video');
      if (!video) return true;
      if (video.paused) { video.play(); } else { video.pause(); }
      return !video.paused;
    })();
    """

    static let off = """
    (function () {
      // The engine may have put the video in its own floating window as well —
      // some players ask for that themselves. Leaving one and not the other
      // leaves you with two.
      try {
        var out = document.querySelector('video[data-lean-picture-in-picture]')
          || document.querySelector('video');
        if (out) {
          if (out.webkitPresentationMode === 'picture-in-picture') {
            out.webkitSetPresentationMode('inline');
          }
          if (document.pictureInPictureElement && document.exitPictureInPicture) {
            document.exitPictureInPicture();
          }
        }
      } catch (e) {}

      clearInterval(window.__leanPictureInPictureWatch);
      window.__leanPictureInPictureWatch = null;
      document.documentElement.classList.remove('lean-picture-in-picture-active');
      var sheet = document.getElementById('lean-picture-in-picture');
      if (sheet) sheet.textContent = '';
      // No DOM nodes were moved on the way out, so there is nothing to put
      // back — just take the mark off whatever still holds it.
      var video = document.querySelector('[data-lean-picture-in-picture]');
      if (video) video.removeAttribute('data-lean-picture-in-picture');
      return 'landed';
    })();
    """

    /// Landing repair, run after `off` completes. While isolated the player
    /// measures a tiny viewport and caches inline sizes; some players
    /// (notably YouTube) never re-measure on return, leaving the video
    /// stuck small inside a full-size player. Purging stale inline sizes
    /// plus a resize event makes the player lay out again — no reload,
    /// no lost playback position.
    static let repair = """
    (function () {
      try {
        var vids = document.querySelectorAll('video');
        for (var i = 0; i < vids.length; i++) {
          vids[i].style.width = '';
          vids[i].style.height = '';
        }
      } catch (e) {}
      try { window.dispatchEvent(new Event('resize')); } catch (e) {}
      return 'repaired';
    })();
    """
}
