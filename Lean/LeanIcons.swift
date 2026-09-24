//
//  LeanIcons.swift
//  Lean
//
//  Custom high-quality fill SVG icons designed for the Lean Browser UI.
//  Resolution-independent vector silhouettes with zero external dependencies.
//

import AppKit
import SwiftUI

public enum LeanIcon: String, CaseIterable, Identifiable, Hashable, Codable {
    case appWindow
    case appleLogo
    case arrowCircleDown
    case arrowCircleRight
    case arrowClockwise
    case arrowCounterClockwise
    case arrowLeft
    case arrowRight
    case arrowSquareOut
    case arrowUpRight
    case arrowsCounterClockwise
    case arrowsOutSimple
    case bookmark
    case bookmarkSimple
    case browser
    case caretDown
    case caretLeft
    case caretRight
    case chatText
    case chats
    case check
    case checkCircle
    case checkSquare
    case circleHalf
    case clock
    case clockCounterClockwise
    case cloud
    case code
    case columns
    case command
    case compass
    case copy
    case cpu
    case dotsThree
    case `extension` = "extension"
    case eyeSlash
    case file
    case fileArchive
    case fileAudio
    case fileCsv
    case fileImage
    case filePdf
    case filePpt
    case fileText
    case fileVideo
    case fire
    case folder
    case folderPlus
    case gear
    case githubLogo
    case hash
    case layout
    case leaf
    case lightning
    case list
    case magnifyingGlass
    case minus
    case minusCircle
    case moon
    case mouse
    case package
    case palette
    case pin
    case pinSlash
    case play
    case plus
    case plusCircle
    case redditLogo
    case shield
    case shieldCheck
    case sidebar
    case slackLogo
    case sliders
    case slidersHorizontal
    case sparkle
    case speakerHigh
    case speakerSlash
    case squaresFour
    case star
    case sun
    case tabs
    case textAlignLeft
    case trash
    case tray
    case warning
    case x
    case xCircle
    case youtubeLogo

    public static let puzzlePiece: LeanIcon = .extension
    public static let extensionIcon: LeanIcon = .extension
    public static let speaker: LeanIcon = .speakerHigh
    public static let speakerMute: LeanIcon = .speakerSlash
    public static let mute: LeanIcon = .speakerSlash
    public static let split: LeanIcon = .columns

    public var id: String { rawValue }

    private static let imageCache = NSCache<NSString, NSImage>()

    /// High-performance AppKit template vector image, cached per icon.
    public var nsImage: NSImage {
        let key = rawValue as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            return cached
        }
        guard let data = svgString.data(using: .utf8),
              let image = NSImage(data: data) else {
            NSLog("Failed to decode Lean icon: %@", rawValue)
            let fallback = NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: rawValue)
                ?? NSImage(size: NSSize(width: 24, height: 24))
            fallback.size = NSSize(width: 24, height: 24)
            fallback.isTemplate = true
            Self.imageCache.setObject(fallback, forKey: key)
            return fallback
        }
        image.size = NSSize(width: 24, height: 24)
        image.isTemplate = true
        Self.imageCache.setObject(image, forKey: key)
        return image
    }

    /// Crisp resizable SwiftUI Image view conforming to foreground tinting.
    public var fill: Image {
        Image(nsImage: nsImage)
            .interpolation(.high)
            .resizable()
    }

    /// Solid fill weight icon variant.
    public var bold: Image {
        fill
    }

    /// Standard UI icon.
    public var uiIcon: Image {
        fill
    }

    /// Underlying SVG source string.
    public var svgString: String {
        Self.svg(for: self)
    }

    public static func svg(for icon: LeanIcon) -> String {
        switch icon {
        case .appWindow:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M3 5.5A2.5 2.5 0 0 1 5.5 3h13A2.5 2.5 0 0 1 21 5.5v13a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 18.5v-13zM6 6.5a1 1 0 1 1-2 0 1 1 0 0 1 2 0zm2.5 0a1 1 0 1 1-2 0 1 1 0 0 1 2 0zm2.5 0a1 1 0 1 1-2 0 1 1 0 0 1 2 0z\"/>\n</svg>"
        case .appleLogo:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M15.5 2.5c0 1.3-.5 2.5-1.4 3.4-.9.9-2.1 1.5-3.4 1.4 0-1.3.5-2.5 1.4-3.4.9-.9 2.2-1.5 3.4-1.4zm3.3 9.4c0-2.4 1.9-3.6 2-3.7-1.1-1.6-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6.1-3.2 1-4 2.5-1.7 3-.4 7.4 1.3 9.7.8 1.2 1.8 2.5 3.1 2.4 1.2 0 1.7-.8 3.1-.8 1.4 0 1.9.8 3.1.8 1.3 0 2.2-1.2 3-2.3 1-1.4 1.4-2.8 1.4-2.8-.1 0-2.6-1-2.6-4z\"/>\n</svg>"
        case .arrowCircleDown:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm1 6a1 1 0 1 0-2 0v5.59l-1.8-1.8a1 1 0 0 0-1.4 1.42l3.5 3.5a1 1 0 0 0 1.4 0l3.5-3.5a1 1 0 0 0-1.4-1.42L13 13.59V8z\"/>\n</svg>"
        case .arrowCircleRight:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm-4 9a1 1 0 1 0 0 2h5.59l-1.8 1.8a1 1 0 0 0 1.42 1.4l3.5-3.5a1 1 0 0 0 0-1.4l-3.5-3.5a1 1 0 0 0-1.42 1.4l1.8 1.8H8z\"/>\n</svg>"
        case .arrowClockwise:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M22.875 5.25v4.5a1.125 1.125 0 0 1-1.125 1.125H17.25a1.125 1.125 0 1 1 0-2.25H18.853l-1.781-1.629c-0.012-0.011-0.024-0.022-0.036-0.035A7.125 7.125 0 1 0 11.906 19.125h0.094a7.081 7.081 0 0 0 4.889-1.942 1.125 1.125 0 0 1 1.546 1.636A9.323 9.323 0 0 1 12 21.375h-0.128A9.375 9.375 0 1 1 18.61 5.349L20.625 7.192V5.25a1.125 1.125 0 0 1 2.25 0Z\"/>\n</svg>"
        case .arrowCounterClockwise:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M21.375 12a9.375 9.375 0 0 1-9.249 9.375H12a9.318 9.318 0 0 1-6.433-2.558 1.125 1.125 0 0 1 1.545-1.636 7.125 7.125 0 1 0-0.147-10.219c-0.012 0.012-0.023 0.023-0.037 0.035L5.146 8.625H6.75a1.125 1.125 0 0 1 0 2.25H2.25a1.125 1.125 0 0 1-1.125-1.125V5.25a1.125 1.125 0 0 1 2.25 0V7.192L5.389 5.349A9.375 9.375 0 0 1 21.375 12Z\"/>\n</svg>"
        case .arrowLeft:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M10.71 4.29a1 1 0 0 0-1.42 0l-6.5 6.5a1 1 0 0 0 0 1.42l6.5 6.5a1 1 0 0 0 1.42-1.42L5.41 12H20a1 1 0 1 0 0-2H5.41l5.3-5.29a1 1 0 0 0 0-1.42z\"/>\n</svg>"
        case .arrowRight:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M13.29 4.29a1 1 0 0 1 1.42 0l6.5 6.5a1 1 0 0 1 0 1.42l-6.5 6.5a1 1 0 0 1-1.42-1.42L18.59 12H4a1 1 0 1 1 0-2h14.59l-5.3-5.29a1 1 0 0 1 0-1.42z\"/>\n</svg>"
        case .arrowSquareOut:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 5.5A2.5 2.5 0 0 1 6.5 3h6a1 1 0 1 1 0 2h-6A.5.5 0 0 0 6 5.5v13a.5.5 0 0 0 .5.5h13a.5.5 0 0 0 .5-.5v-6a1 1 0 1 1 2 0v6a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 4 18.5v-13z\"/>\n  <path d=\"M14 4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v6a1 1 0 1 1-2 0V6.41l-7.29 7.3a1 1 0 1 1-1.42-1.42l7.3-7.29H15a1 1 0 0 1-1-1z\"/>\n</svg>"
        case .arrowUpRight:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M6.3 19.1a1.25 1.25 0 0 1-.88-2.13L15.3 7H9a1.25 1.25 0 1 1 0-2.5h9.75a1.25 1.25 0 0 1 1.25 1.25V15.5a1.25 1.25 0 1 1-2.5 0V9.2L7.18 19.46a1.25 1.25 0 0 1-.88.36z\"/>\n</svg>"
        case .arrowsCounterClockwise:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M12 2a10 10 0 0 0-7.3 3.2L2.5 3v6h6L5.8 6.3A7.5 7.5 0 0 1 19.5 12h2.5A10 10 0 0 0 12 2zm7.5 13-2.7 2.7A7.5 7.5 0 0 1 4.5 12H2a10 10 0 0 0 17.3 6.8l2.2 2.2v-6h-6z\"/>\n</svg>"
        case .arrowsOutSimple:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M3.5 3.5A1 1 0 0 1 4.5 2.5h5a1 1 0 1 1 0 2H6.41l3.3 3.3a1 1 0 0 1-1.42 1.4l-3.3-3.3v3.09a1 1 0 1 1-2 0v-5a1 1 0 0 1 .5-.9zM19.5 2.5a1 1 0 0 1 1 1v5a1 1 0 1 1-2 0V5.41l-3.3 3.3a1 1 0 0 1-1.4-1.42l3.3-3.3h-3.1a1 1 0 1 1 0-2h5a1 1 0 0 1 .5.01zM8.3 14.3a1 1 0 0 1 1.4 1.4l-3.3 3.3h3.1a1 1 0 1 1 0 2h-5a1 1 0 0 1-1-1v-5a1 1 0 1 1 2 0v3.09l3.3-3.3zm7.4 0a1 1 0 0 1 1.42 0l3.3 3.3v-3.1a1 1 0 1 1 2 0v5a1 1 0 0 1-1 1h-5a1 1 0 1 1 0-2h3.09l-3.3-3.3a1 1 0 0 1 0-1.4z\"/>\n</svg>"
        case .bookmark:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M5 3.5A2.5 2.5 0 0 1 7.5 1h9A2.5 2.5 0 0 1 19 3.5v18a1 1 0 0 1-1.57.82L12 18.25l-5.43 4.07A1 1 0 0 1 5 21.5v-18z\"/>\n</svg>"
        case .bookmarkSimple:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M6 3.5A2.5 2.5 0 0 1 8.5 1h7A2.5 2.5 0 0 1 18 3.5v18a1 1 0 0 1-1.58.82L12 18.27l-4.42 3.05A1 1 0 0 1 6 21.5v-18zm2.5-.5a.5.5 0 0 0-.5.5v15.74l3.42-2.36a1 1 0 0 1 1.16 0l3.42 2.36V3.5a.5.5 0 0 0-.5-.5h-7z\"/>\n</svg>"
        case .browser:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M5.5 3A3.5 3.5 0 0 0 2 6.5v11A3.5 3.5 0 0 0 5.5 21h13a3.5 3.5 0 0 0 3.5-3.5v-11A3.5 3.5 0 0 0 18.5 3h-13zM4 9h16v8.5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5V9zm2-2.5a1 1 0 1 0 0-2 1 1 0 0 0 0 2zm3 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2zm3 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2z\"/>\n</svg>"
        case .caretDown:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M4.8 8.5a1.25 1.25 0 0 0-1.05 1.92l7.2 7.88a1.25 1.25 0 0 0 2.1 0l7.2-7.88A1.25 1.25 0 0 0 19.2 8.5H4.8z\"/>\n</svg>"
        case .caretLeft:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M15.5 4.8a1.25 1.25 0 0 0-1.92-1.05L5.7 10.95a1.25 1.25 0 0 0 0 2.1l7.88 7.2a1.25 1.25 0 0 0 1.92-1.05V4.8z\"/>\n</svg>"
        case .caretRight:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M8.5 4.8a1.25 1.25 0 0 1 1.92-1.05l7.88 7.2a1.25 1.25 0 0 1 0 2.1l-7.88 7.2A1.25 1.25 0 0 1 8.5 19.2V4.8z\"/>\n</svg>"
        case .chatText:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M18.5 3H5.5A3.5 3.5 0 0 0 2 6.5v8A3.5 3.5 0 0 0 5.5 18H7v3.5a1 1 0 0 0 1.6.8L13 18h5.5a3.5 3.5 0 0 0 3.5-3.5v-8A3.5 3.5 0 0 0 18.5 3zM6 8a1 1 0 0 1 1-1h10a1 1 0 1 1 0 2H7a1 1 0 0 1-1-1zm0 4a1 1 0 0 1 1-1h6a1 1 0 1 1 0 2H7a1 1 0 0 1-1-1z\"/>\n</svg>"
        case .chats:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M18.5 2H6.5A3.5 3.5 0 0 0 3 5.5v7A3.5 3.5 0 0 0 6.5 16H8v3.5a1 1 0 0 0 1.6.8L14 16h4.5a3.5 3.5 0 0 0 3.5-3.5v-7A3.5 3.5 0 0 0 18.5 2z\"/>\n  <path d=\"M6 18v2.5a1 1 0 0 0 1.6.8L11 18H6z\" opacity=\"0.6\"/>\n</svg>"
        case .check:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M20.28 6.22a1.25 1.25 0 0 1 0 1.77l-10.5 10.5a1.25 1.25 0 0 1-1.77 0l-4.5-4.5a1.25 1.25 0 0 1 1.77-1.77L9 15.94l9.51-9.72a1.25 1.25 0 0 1 1.77 0z\"/>\n</svg>"
        case .checkCircle:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm4.7 7.7a1 1 0 0 0-1.4-1.4L10.5 13.1l-1.8-1.8a1 1 0 0 0-1.4 1.4l2.5 2.5a1 1 0 0 0 1.4 0l5.5-5.5z\"/>\n</svg>"
        case .checkSquare:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M6 3h12a3 3 0 0 1 3 3v12a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3zm10.7 6.7a1 1 0 0 0-1.4-1.4L10.5 13.1l-1.8-1.8a1 1 0 0 0-1.4 1.4l2.5 2.5a1 1 0 0 0 1.4 0l5.5-5.5z\"/>\n</svg>"
        case .circleHalf:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm0 2.5a7.5 7.5 0 0 0 0 15V4.5z\"/>\n</svg>"
        case .clock:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm1 5a1 1 0 1 0-2 0v5a1 1 0 0 0 .5.87l3.5 2a1 1 0 1 0 1-1.74L13 11.6V7z\"/>\n</svg>"
        case .clockCounterClockwise:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M13.125 7.5v3.863l3.203 1.922a1.125 1.125 0 1 1-1.157 1.929l-3.75-2.25A1.125 1.125 0 0 1 10.875 12V7.5a1.125 1.125 0 0 1 2.25 0ZM12 2.625A9.317 9.317 0 0 0 5.366 5.376c-0.44 0.444-0.844 0.878-1.241 1.312V6a1.125 1.125 0 0 0-2.25 0v3.75a1.125 1.125 0 0 0 1.125 1.125H6.75a1.125 1.125 0 0 0 0-2.25H5.416C5.906 8.062 6.41 7.521 6.962 6.962a7.125 7.125 0 1 1 0.148 10.219 1.125 1.125 0 0 0-1.545 1.637A9.375 9.375 0 1 0 12 2.625Z\"/>\n</svg>"
        case .cloud:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path transform=\"translate(1 1) scale(0.9167)\" d=\"M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z\"/>\n</svg>"
        case .code:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M8.7 5.3a1 1 0 0 0-1.4 0l-5 5a1 1 0 0 0 0 1.4l5 5a1 1 0 0 0 1.4-1.4L4.4 11l4.3-4.3a1 1 0 0 0 0-1.4zm6.6 0a1 1 0 0 1 1.4 0l5 5a1 1 0 0 1 0 1.4l-5 5a1 1 0 0 1-1.4-1.4l4.3-4.3-4.3-4.3a1 1 0 0 1 0-1.4zM13.8 3.2a1 1 0 0 1 .8 1.2l-3.5 16a1 1 0 0 1-2-.4l3.5-16a1 1 0 0 1 1.2-.8z\"/>\n</svg>"
        case .columns:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v13a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 18.5v-13zM6.5 4.5a1 1 0 0 0-1 1v13a1 1 0 0 0 1 1H11V4.5H6.5zm6 15h4.5a1 1 0 0 0 1-1v-13a1 1 0 0 0-1-1H12.5v15z\"/>\n</svg>"
        case .command:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M6 3.5A3.5 3.5 0 0 0 2.5 7 3.5 3.5 0 0 0 6 10.5h1.5v3H6A3.5 3.5 0 0 0 2.5 17 3.5 3.5 0 0 0 6 20.5 3.5 3.5 0 0 0 9.5 17v-1.5h5V17a3.5 3.5 0 0 0 3.5 3.5 3.5 3.5 0 0 0 3.5-3.5 3.5 3.5 0 0 0-3.5-3.5H16.5v-3H18A3.5 3.5 0 0 0 21.5 7 3.5 3.5 0 0 0 18 3.5 3.5 3.5 0 0 0 14.5 7v1.5h-5V7A3.5 3.5 0 0 0 6 3.5zm3.5 6H6A1.5 1.5 0 0 1 4.5 8 1.5 1.5 0 0 1 6 6.5 1.5 1.5 0 0 1 7.5 8v1.5h2zm5 0h-5v5h5v-5zm2-1.5V8A1.5 1.5 0 0 1 18 6.5 1.5 1.5 0 0 1 19.5 8 1.5 1.5 0 0 1 18 9.5h-1.5zM6 15.5h1.5V17A1.5 1.5 0 0 1 6 18.5 1.5 1.5 0 0 1 4.5 17 1.5 1.5 0 0 1 6 15.5zm10.5 1.5v-1.5H18A1.5 1.5 0 0 1 19.5 17 1.5 1.5 0 0 1 18 18.5a1.5 1.5 0 0 1-1.5-1.5z\"/>\n</svg>"
        case .compass:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm3.89 6.11a1 1 0 0 0-1-.27l-5.5 1.83a1 1 0 0 0-.63.63l-1.83 5.5a1 1 0 0 0 1.27 1.27l5.5-1.83a1 1 0 0 0 .63-.63l1.83-5.5a1 1 0 0 0-.27-1zM12 10.75a1.25 1.25 0 1 1 0 2.5 1.25 1.25 0 0 1 0-2.5z\"/>\n</svg>"
        case .copy:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M7.5 3A2.5 2.5 0 0 0 5 5.5v9A2.5 2.5 0 0 0 7.5 17H8v-7.5A3.5 3.5 0 0 1 11.5 6H16v-.5A2.5 2.5 0 0 0 13.5 3h-6z\"/>\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M11.5 8A2.5 2.5 0 0 0 9 10.5v8A2.5 2.5 0 0 0 11.5 21h7a2.5 2.5 0 0 0 2.5-2.5v-8A2.5 2.5 0 0 0 18.5 8h-7z\"/>\n</svg>"
        case .cpu:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M9 2a1 1 0 0 1 1 1v2h4V3a1 1 0 1 1 2 0v2h1.5A2.5 2.5 0 0 1 20 7.5V9h2a1 1 0 1 1 0 2h-2v2h2a1 1 0 1 1 0 2h-2v1.5a2.5 2.5 0 0 1-2.5 2.5H16v2a1 1 0 1 1-2 0v-2h-4v2a1 1 0 1 1-2 0v-2H6.5A2.5 2.5 0 0 1 4 16.5V15H2a1 1 0 1 1 0-2h2v-2H2a1 1 0 1 1 0-2h2V7.5A2.5 2.5 0 0 1 6.5 5H8V3a1 1 0 0 1 1-1zM7 7.5a.5.5 0 0 1 .5-.5h9a.5.5 0 0 1 .5.5v9a.5.5 0 0 1-.5.5h-9a.5.5 0 0 1-.5-.5v-9zm2 2a.5.5 0 0 1 .5-.5h5a.5.5 0 0 1 .5.5v5a.5.5 0 0 1-.5.5h-5a.5.5 0 0 1-.5-.5v-5z\"/>\n</svg>"
        case .dotsThree:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <circle cx=\"5\" cy=\"12\" r=\"2\"/>\n  <circle cx=\"12\" cy=\"12\" r=\"2\"/>\n  <circle cx=\"19\" cy=\"12\" r=\"2\"/>\n</svg>"
        case .extension:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M20.5 11H19V7c0-1.1-.9-2-2-2h-4V3.5C13 2.12 11.88 1 10.5 1S8 2.12 8 3.5V5H4c-1.1 0-1.99.9-1.99 2v3.8H3.5c1.49 0 2.7 1.21 2.7 2.7s-1.21 2.7-2.7 2.7H2V20c0 1.1.9 2 2 2h3.8v-1.5c0-1.49 1.21-2.7 2.7-2.7 1.49 0 2.7 1.21 2.7 2.7V22H17c1.1 0 2-.9 2-2v-4h1.5c1.38 0 2.5-1.12 2.5-2.5s-1.12-2.5-2.5-2.5z\"/>\n</svg>"
        case .eyeSlash:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M3.7 2.3a1 1 0 0 0-1.4 1.4l18 18a1 1 0 0 0 1.4-1.4L18.4 17A11.75 11.75 0 0 0 22 12c-1.8-4.2-6.1-7-10-7-2 0-3.9.7-5.5 1.8L3.7 2.3zM12 7c2.9 0 6.2 2 7.7 5a8.7 8.7 0 0 1-3.1 3.5l-2.4-2.4A3.5 3.5 0 0 0 10.9 9.8L8.6 7.5C9.7 7.2 10.8 7 12 7zm-5.4 3.2 2.1 2.1a3.5 3.5 0 0 0 4.6 4.6l1.7 1.7C13.8 19 12.9 19 12 19c-3.9 0-8.2-2.8-10-7a11.9 11.9 0 0 1 4.6-5.8z\"/>\n</svg>"
        case .file:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5z\"/>\n</svg>"
        case .fileArchive:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM11 10h2v1.5h-2V10zm0 2.5h2V14h-2v-1.5zm0 2.5h2v2a1 1 0 0 1-2 0v-2z\"/>\n</svg>"
        case .fileAudio:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM12 11a1 1 0 0 1 1 1v3.18A2.5 2.5 0 1 1 11 13V12a1 1 0 0 1 1-1z\"/>\n</svg>"
        case .fileCsv:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM8 11h8v1.5H8V11zm0 3h8v1.5H8V14z\"/>\n</svg>"
        case .fileImage:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM8 12.5a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0zm9 5.5H7l3.5-4.5 2 2.5 1.5-1.5 3 3.5z\"/>\n</svg>"
        case .filePdf:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM7.5 12h3a1.5 1.5 0 0 1 0 3h-2v2.5a.75.75 0 0 1-1.5 0v-5a.75.75 0 0 1 .5-.5zm1 1.5v-1.5h1.5a.5.5 0 0 1 0 1h-1.5zm5.5-1.5h2a1.5 1.5 0 0 1 1.5 1.5v2a1.5 1.5 0 0 1-1.5 1.5h-2a.75.75 0 0 1-.75-.75v-3.5a.75.75 0 0 1 .75-.75zm.75 1.5v2h1.25a.25.25 0 0 0 .25-.25v-1.5a.25.25 0 0 0-.25-.25h-1.25z\"/>\n</svg>"
        case .filePpt:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM8 11h3a2 2 0 0 1 0 4H8v3H6.5v-7H8zm0 1.5v1h3a.5.5 0 0 0 0-1H8z\"/>\n</svg>"
        case .fileText:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM8 12a1 1 0 0 1 1-1h6a1 1 0 1 1 0 2H9a1 1 0 0 1-1-1zm0 3.5a1 1 0 0 1 1-1h6a1 1 0 1 1 0 2H9a1 1 0 0 1-1-1z\"/>\n</svg>"
        case .fileVideo:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2H14l6 6v11.5a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-15zM13.5 3.5V8H18l-4.5-4.5zM10 11.5a1 1 0 0 1 1.5-.86l4 2.5a1 1 0 0 1 0 1.72l-4 2.5A1 1 0 0 1 10 16.5v-5z\"/>\n</svg>"
        case .fire:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M12.5 2c-.3 1.5-.7 2.8-1.5 4-1.2 1.8-2.5 3.3-3.5 5.5-1.1 2.3-1.5 4.3-.8 6.5.9 2.7 3.3 4 5.8 4 3.7 0 6.5-2.8 6.5-6.5 0-3.3-2-6.5-3.8-9-.8 1.5-1.6 2.5-2.2 2.5-.5 0-.8-.5-.8-1.3 0-1.8.8-4.2.3-5.7z\"/>\n</svg>"
        case .folder:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M2.5 5A2.5 2.5 0 0 1 5 2.5h3.6a2.5 2.5 0 0 1 1.77.73L12 4.85h7A2.5 2.5 0 0 1 21.5 7.35v11.15a2.5 2.5 0 0 1-2.5 2.5H5a2.5 2.5 0 0 1-2.5-2.5V5z\"/>\n</svg>"
        case .folderPlus:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M2.5 5A2.5 2.5 0 0 1 5 2.5h3.6a2.5 2.5 0 0 1 1.77.73L12 4.85h7A2.5 2.5 0 0 1 21.5 7.35v11.15a2.5 2.5 0 0 1-2.5 2.5H5a2.5 2.5 0 0 1-2.5-2.5V5zm9.5 4a.75.75 0 0 1 .75.75V12h2.25a.75.75 0 0 1 0 1.5H12.75v2.25a.75.75 0 0 1-1.5 0V13.5H9a.75.75 0 0 1 0-1.5h2.25V9.75A.75.75 0 0 1 12 9z\"/>\n</svg>"
        case .gear:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M22.307 10.051a0.75 0.75 0 0 0-0.365-0.506l-2.797-1.594-0.011-3.152a0.75 0.75 0 0 0-0.265-0.57 10.492 10.492 0 0 0-3.442-1.938 0.75 0.75 0 0 0-0.606 0.055L12 3.923 9.176 2.344a0.75 0.75 0 0 0-0.607-0.056A10.492 10.492 0 0 0 5.131 4.233a0.75 0.75 0 0 0-0.265 0.569l-0.014 3.155-2.797 1.594a0.75 0.75 0 0 0-0.365 0.506 9.982 9.982 0 0 0 0 3.896 0.75 0.75 0 0 0 0.365 0.506l2.797 1.594 0.011 3.153a0.75 0.75 0 0 0 0.265 0.57 10.492 10.492 0 0 0 3.442 1.938 0.75 0.75 0 0 0 0.606-0.055L12 20.077 14.824 21.656a0.742 0.742 0 0 0 0.366 0.094 0.758 0.758 0 0 0 0.241-0.039 10.509 10.509 0 0 0 3.439-1.943 0.75 0.75 0 0 0 0.265-0.569l0.014-3.155 2.797-1.594a0.75 0.75 0 0 0 0.365-0.506A9.982 9.982 0 0 0 22.307 10.051ZM12 15.75a3.75 3.75 0 1 1 3.75-3.75A3.75 3.75 0 0 1 12 15.75Z\"/>\n</svg>"
        case .githubLogo:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.53 1.032 1.53 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0 0 22 12.017C22 6.484 17.522 2 12 2z\"/>\n</svg>"
        case .hash:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M9.8 4a1 1 0 0 1 1 .86L10.3 8h4.4l-.5-3.14a1 1 0 1 1 2 .32L16.5 8H20a1 1 0 1 1 0 2h-3.8l-.6 4H19a1 1 0 1 1 0 2h-3.8l-.5 3.14a1 1 0 1 1-2-.32L13 16H8.6l-.5 3.14a1 1 0 1 1-2-.32L6.5 16H4a1 1 0 1 1 0-2h2.8l.6-4H4a1 1 0 1 1 0-2h3.8l.5-3.14A1 1 0 0 1 9.8 4zm1 6-.6 4h4.4l.6-4h-4.4z\"/>\n</svg>"
        case .layout:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M3 5.5A2.5 2.5 0 0 1 5.5 3h13A2.5 2.5 0 0 1 21 5.5v13a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 18.5v-13zM5.5 5h13a.5.5 0 0 1 .5.5V8H5V5.5a.5.5 0 0 1 .5-.5zM5 10v8.5a.5.5 0 0 0 .5.5h13a.5.5 0 0 0 .5-.5V10H5z\"/>\n</svg>"
        case .leaf:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M20.9 3.1c-6.8-.7-13.8 2.5-17.1 8.8-1.7 3.3-1.6 7 .6 9.2s5.9 2.3 9.2.6c6.3-3.3 9.5-10.3 8.8-17.1a1 1 0 0 0-1.5-1.5zm-8.8 15.8c-2.3 1.1-4.7.7-6.2-.8s-1.9-3.9-.8-6.2c2.4-4.8 7.6-7.8 13.1-8.1-.3 5.5-3.3 10.7-8.1 13.1z\"/>\n  <path d=\"M4 20c3-3 7-4.5 11-4.5\"/>\n</svg>"
        case .lightning:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M12.5 2a1 1 0 0 0-.92.62L6.1 13.62A1 1 0 0 0 7 15h4v6a1 1 0 0 0 1.76.65l7.5-8.5A1 1 0 0 0 19.5 11.5H15V3a1 1 0 0 0-1-1h-1.5z\"/>\n</svg>"
        case .list:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M4 6a1.25 1.25 0 0 1 1.25-1.25h14.5a1.25 1.25 0 1 1 0 2.5H5.25A1.25 1.25 0 0 1 4 6zm0 6a1.25 1.25 0 0 1 1.25-1.25h14.5a1.25 1.25 0 1 1 0 2.5H5.25A1.25 1.25 0 0 1 4 12zm0 6a1.25 1.25 0 0 1 1.25-1.25h14.5a1.25 1.25 0 1 1 0 2.5H5.25A1.25 1.25 0 0 1 4 18z\"/>\n</svg>"
        case .magnifyingGlass:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M10.5 3.5a7 7 0 1 0 4.29 12.52l4.49 4.49a1.25 1.25 0 0 0 1.77-1.77l-4.49-4.49A7 7 0 0 0 10.5 3.5zm-4.5 7a4.5 4.5 0 1 1 9 0 4.5 4.5 0 0 1-9 0z\"/>\n</svg>"
        case .minus:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M4.75 12a1.25 1.25 0 0 1 1.25-1.25h12a1.25 1.25 0 1 1 0 2.5H6a1.25 1.25 0 0 1-1.25-1.25z\"/>\n</svg>"
        case .minusCircle:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm-4 9a1 1 0 1 0 0 2h8a1 1 0 1 0 0-2H8z\"/>\n</svg>"
        case .moon:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M22.082 14.082a9.829 9.829 0 0 1-3.469 4.96A9.75 9.75 0 0 1 3 11.25 9.665 9.665 0 0 1 4.958 5.389a9.829 9.829 0 0 1 4.96-3.469 0.75 0.75 0 0 1 0.938 0.938 8.258 8.258 0 0 0 10.294 10.294 0.75 0.75 0 0 1 0.938 0.938Z\"/>\n</svg>"
        case .mouse:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M6 8a6 6 0 0 1 12 0v8a6 6 0 0 1-12 0V8zm5-3a1 1 0 0 1 2 0v3a1 1 0 1 1-2 0V5z\"/>\n</svg>"
        case .package:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M11.5 2.2a1 1 0 0 1 1 0l8.5 4.9a1 1 0 0 1 .5.87v9.8a1 1 0 0 1-.5.87l-8.5 4.9a1 1 0 0 1-1 0l-8.5-4.9a1 1 0 0 1-.5-.87v-9.8a1 1 0 0 1 .5-.87l8.5-4.9zM12 4.47 5.03 8.5 12 12.53l6.97-4.03L12 4.47zM4 10.24v6.02l7 4.04v-6.02l-7-4.04zm9 10.06 7-4.04v-6.02l-7 4.04v6.02z\"/>\n</svg>"
        case .palette:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.48 2 2 6.48 2 12c0 4.14 2.54 7.69 6.17 9.17a2.5 2.5 0 0 0 3.33-2.38v-.79c0-.69.56-1.25 1.25-1.25h1.75a6.5 6.5 0 0 0 6.5-6.5C21 6.36 16.97 2 12 2zm-5.5 8a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0zm4-4a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0zm5 2a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0zm2 5a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0z\"/>\n</svg>"
        case .pin:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M16 12V4h1a1 1 0 0 0 0-2H7a1 1 0 0 0 0 2h1v8l-2 3v2h5v6a1 1 0 0 0 2 0v-6h5v-2l-2-3z\"/>\n</svg>"
        case .pinSlash:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M2.71 2.29a1 1 0 0 0-1.42 1.42l4.8 4.8V12l-2 3v2h5v6a1 1 0 0 0 2 0v-6h1.09l4.6 4.6a1 1 0 0 0 1.42-1.42L2.71 2.29zM16 12V4h1a1 1 0 0 0 0-2H7a1 1 0 0 0-.82.43l9.82 9.82V12z\"/>\n</svg>"
        case .play:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M6.5 4.8a1.5 1.5 0 0 1 2.27-1.29l11.5 7.2a1.5 1.5 0 0 1 0 2.58l-11.5 7.2A1.5 1.5 0 0 1 6.5 19.2V4.8z\"/>\n</svg>"
        case .plus:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M12 4a1.25 1.25 0 0 1 1.25 1.25v5.5h5.5a1.25 1.25 0 1 1 0 2.5h-5.5v5.5a1.25 1.25 0 1 1-2.5 0v-5.5h-5.5a1.25 1.25 0 1 1 0-2.5h5.5v-5.5A1.25 1.25 0 0 1 12 4z\"/>\n</svg>"
        case .plusCircle:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm1 6a1 1 0 1 0-2 0v3H8a1 1 0 1 0 0 2h3v3a1 1 0 1 0 2 0v-3h3a1 1 0 1 0 0-2h-3V8z\"/>\n</svg>"
        case .redditLogo:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <circle cx=\"12\" cy=\"14\" r=\"8\"/>\n  <circle cx=\"3.5\" cy=\"12\" r=\"2.5\"/>\n  <circle cx=\"20.5\" cy=\"12\" r=\"2.5\"/>\n  <circle cx=\"19\" cy=\"4\" r=\"2\"/>\n  <path d=\"M12 9l2-5 3.5 1\" stroke=\"currentColor\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" fill=\"none\"/>\n</svg>"
        case .shield:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M12 2a1 1 0 0 1 .37.07l8 3.2A1 1 0 0 1 21 6.2v6.55c0 5.4-3.66 9.53-8.62 11.2a1 1 0 0 1-.76 0C6.66 22.28 3 18.15 3 12.75V6.2a1 1 0 0 1 .63-.93l8-3.2A1 1 0 0 1 12 2z\"/>\n</svg>"
        case .shieldCheck:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2a1 1 0 0 1 .37.07l8 3.2A1 1 0 0 1 21 6.2v6.55c0 5.4-3.66 9.53-8.62 11.2a1 1 0 0 1-.76 0C6.66 22.28 3 18.15 3 12.75V6.2a1 1 0 0 1 .63-.93l8-3.2A1 1 0 0 1 12 2zm3.7 8.7a1 1 0 0 0-1.4-1.4L11 12.6l-1.3-1.3a1 1 0 0 0-1.4 1.4l2 2a1 1 0 0 0 1.4 0l4-4z\"/>\n</svg>"
        case .sidebar:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M5.5 3A3.5 3.5 0 0 0 2 6.5v11A3.5 3.5 0 0 0 5.5 21h13a3.5 3.5 0 0 0 3.5-3.5v-11A3.5 3.5 0 0 0 18.5 3h-13zM4 6.5C4 5.67 4.67 5 5.5 5H8v14H5.5A1.5 1.5 0 0 1 4 17.5v-11zm5.5 12.5V5h9a1.5 1.5 0 0 1 1.5 1.5v11a1.5 1.5 0 0 1-1.5 1.5h-9z\"/>\n</svg>"
        case .slackLogo:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M5.5 10.5C6.9 10.5 8 9.4 8 8V5.5C8 4.1 6.9 3 5.5 3S3 4.1 3 5.5 4.1 8 5.5 8H8\"/>\n  <path d=\"M9.5 5.5C9.5 4.1 10.6 3 12 3s2.5 1.1 2.5 2.5v5c0 1.4-1.1 2.5-2.5 2.5s-2.5-1.1-2.5-2.5v-5z\"/>\n  <path d=\"M13.5 18.5C13.5 17.1 14.6 16 16 16h2.5c1.4 0 2.5 1.1 2.5 2.5s-1.1 2.5-2.5 2.5H16c-1.4 0-2.5-1.1-2.5-2.5z\"/>\n  <path d=\"M18.5 14.5c1.4 0 2.5-1.1 2.5-2.5s-1.1-2.5-2.5-2.5h-5c-1.4 0-2.5 1.1-2.5 2.5s1.1 2.5 2.5 2.5h5z\"/>\n  <path d=\"M5.5 13.5C4.1 13.5 3 14.6 3 16s1.1 2.5 2.5 2.5H8V16c0-1.4-1.1-2.5-2.5-2.5z\"/>\n</svg>"
        case .sliders:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M6.5 3a1 1 0 0 1 1 1v4.1a3 3 0 0 1 0 5.8V20a1 1 0 1 1-2 0v-6.1a3 3 0 0 1 0-5.8V4a1 1 0 0 1 1-1zm-1.5 8a1.5 1.5 0 1 0 3 0 1.5 1.5 0 0 0-3 0zm11.5-8a1 1 0 0 1 1 1v10.1a3 3 0 0 1 0 5.8V20a1 1 0 1 1-2 0v-3.1a3 3 0 0 1 0-5.8V4a1 1 0 0 1 1-1zm1.5 14a1.5 1.5 0 1 0-3 0 1.5 1.5 0 0 0 3 0z\"/>\n</svg>"
        case .slidersHorizontal:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M3 6.5a1 1 0 0 1 1-1h4.1a3 3 0 0 1 5.8 0H20a1 1 0 1 1 0 2h-6.1a3 3 0 0 1-5.8 0H4a1 1 0 0 1-1-1zm8 1.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM3 16.5a1 1 0 0 1 1-1h10.1a3 3 0 0 1 5.8 0H20a1 1 0 1 1 0 2h-.1a3 3 0 0 1-5.8 0H4a1 1 0 0 1-1-1zm14 1.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z\"/>\n</svg>"
        case .sparkle:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M12 2c.4 5.3 4.7 9.6 10 10-5.3.4-9.6 4.7-10 10-.4-5.3-4.7-9.6-10-10 5.3-.4 9.6-4.7 10-10z\"/>\n</svg>"
        case .speakerHigh:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M14 3.23a1 1 0 0 0-1.09.21L7.62 8H4a2 2 0 0 0-2 2v4a2 2 0 0 0 2 2h3.62l5.29 4.56A1 1 0 0 0 14 20.77V3.23zM18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM16 4.13v2.06a6.01 6.01 0 0 1 0 11.62v2.06c4.01-.91 7-4.49 7-8.87s-2.99-7.96-7-8.87z\"/>\n</svg>"
        case .speakerSlash:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M3.28 2.22a.75.75 0 0 0-1.06 1.06l3.15 3.15L5.09 6.64A1 1 0 0 0 4 7.4v9.2a1 1 0 0 0 1.62.78l4.47-3.57 9.63 9.63a.75.75 0 0 0 1.06-1.06L3.28 2.22zM8.9 12.35 5.5 15.07V8.93l2.84 2.84.56.58zM14 3.23a1 1 0 0 0-1.09.21L8.85 7.02l1.09 1.09 3.06-2.63v8.66l2 2V3.23zM18.5 12c0-1.77-1.02-3.29-2.5-4.03v2.45l2.45 2.45c.03-.29.05-.58.05-.87z\"/>\n</svg>"
        case .squaresFour:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <rect x=\"3\" y=\"3\" width=\"7.5\" height=\"7.5\" rx=\"2\"/>\n  <rect x=\"13.5\" y=\"3\" width=\"7.5\" height=\"7.5\" rx=\"2\"/>\n  <rect x=\"3\" y=\"13.5\" width=\"7.5\" height=\"7.5\" rx=\"2\"/>\n  <rect x=\"13.5\" y=\"13.5\" width=\"7.5\" height=\"7.5\" rx=\"2\"/>\n</svg>"
        case .star:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M12 2.25a.75.75 0 0 1 .67.42l2.67 5.4 5.96.87a.75.75 0 0 1 .42 1.28l-4.32 4.2 1.02 5.94a.75.75 0 0 1-1.09.79L12 18.35l-5.33 2.8a.75.75 0 0 1-1.09-.79l1.02-5.94-4.32-4.2a.75.75 0 0 1 .42-1.28l5.96-.87 2.67-5.4a.75.75 0 0 1 .67-.42z\"/>\n</svg>"
        case .sun:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M11.25 3.75V1.5a0.75 0.75 0 0 1 1.5 0V3.75a0.75 0.75 0 0 1-1.5 0Zm0.75 2.25a6 6 0 1 0 6 6A6.007 6.007 0 0 0 12 6ZM5.469 6.531A0.75 0.75 0 0 0 6.531 5.469l-1.5-1.5A0.75 0.75 0 0 0 3.969 5.031Zm0 10.939-1.5 1.5a0.75 0.75 0 0 0 1.061 1.061l1.5-1.5a0.75 0.75 0 0 0-1.061-1.061ZM18 6.75a0.75 0.75 0 0 0 0.531-0.219l1.5-1.5a0.75 0.75 0 0 0-1.061-1.061l-1.5 1.5A0.75 0.75 0 0 0 18 6.75Zm0.531 10.719a0.75 0.75 0 0 0-1.061 1.061l1.5 1.5a0.75 0.75 0 0 0 1.061-1.061ZM4.5 12a0.75 0.75 0 0 0-0.75-0.75H1.5a0.75 0.75 0 0 0 0 1.5H3.75A0.75 0.75 0 0 0 4.5 12Zm7.5 7.5a0.75 0.75 0 0 0-0.75 0.75v2.25a0.75 0.75 0 0 0 1.5 0V20.25A0.75 0.75 0 0 0 12 19.5Zm10.5-8.25H20.25a0.75 0.75 0 0 0 0 1.5h2.25a0.75 0.75 0 0 0 0-1.5Z\"/>\n</svg>"
        case .tabs:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M4 4.5A2.5 2.5 0 0 1 6.5 2h9A2.5 2.5 0 0 1 18 4.5V6H6.5A3.5 3.5 0 0 0 3 9.5V17h-.5A2.5 2.5 0 0 1 0 14.5v-7A2.5 2.5 0 0 1 2.5 5H4v-.5z\"/>\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M6.5 7A2.5 2.5 0 0 0 4 9.5v9A2.5 2.5 0 0 0 6.5 21h12a2.5 2.5 0 0 0 2.5-2.5v-9A2.5 2.5 0 0 0 18.5 7h-12z\"/>\n</svg>"
        case .textAlignLeft:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M4 6a1.25 1.25 0 0 1 1.25-1.25h14.5a1.25 1.25 0 1 1 0 2.5H5.25A1.25 1.25 0 0 1 4 6zm0 6a1.25 1.25 0 0 1 1.25-1.25h10.5a1.25 1.25 0 1 1 0 2.5H5.25A1.25 1.25 0 0 1 4 12zm0 6a1.25 1.25 0 0 1 1.25-1.25h7.5a1.25 1.25 0 1 1 0 2.5H5.25A1.25 1.25 0 0 1 4 18z\"/>\n</svg>"
        case .trash:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M9 3a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v1h4.5a1 1 0 1 1 0 2H19l-.9 13.1A3 3 0 0 1 15.1 22H8.9a3 3 0 0 1-2.99-2.9L5 6H4.5a1 1 0 0 1 0-2H9V3zm2 1h2V4h-2V4zm-1.5 5a.8.8 0 0 1 .8.8v8.4a.8.8 0 1 1-1.6 0V9.8a.8.8 0 0 1 .8-.8zm4.5 0a.8.8 0 0 1 .8.8v8.4a.8.8 0 1 1-1.6 0V9.8a.8.8 0 0 1 .8-.8z\"/>\n</svg>"
        case .tray:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M3.5 4A2.5 2.5 0 0 0 1 6.5v11A2.5 2.5 0 0 0 3.5 20h17a2.5 2.5 0 0 0 2.5-2.5v-11A2.5 2.5 0 0 0 20.5 4h-17zm17 9H16a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2H3.5v4.5a.5.5 0 0 0 .5.5h16a.5.5 0 0 0 .5-.5V13z\"/>\n</svg>"
        case .warning:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M10.27 3.48a2 2 0 0 1 3.46 0l8.5 15.3A2 2 0 0 1 20.49 22H3.51a2 2 0 0 1-1.74-3.22l8.5-15.3zm1.73 4.52a1 1 0 0 0-1 1v5a1 1 0 1 0 2 0V9a1 1 0 0 0-1-1zm0 9a1.25 1.25 0 1 0 0-2.5 1.25 1.25 0 0 0 0 2.5z\"/>\n</svg>"
        case .x:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path d=\"M6.22 4.8a1 1 0 0 0-1.42 1.42L10.59 12l-5.79 5.78a1 1 0 1 0 1.42 1.42L12 13.41l5.78 5.79a1 1 0 0 0 1.42-1.42L13.41 12l5.79-5.78a1 1 0 0 0-1.42-1.42L12 10.59 6.22 4.8z\"/>\n</svg>"
        case .xCircle:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm3.7 6.3a1 1 0 0 0-1.4 0L12 10.6 9.7 8.3a1 1 0 0 0-1.4 1.4l2.3 2.3-2.3 2.3a1 1 0 1 0 1.4 1.4l2.3-2.3 2.3 2.3a1 1 0 0 0 1.4-1.4L13.4 12l2.3-2.3a1 1 0 0 0 0-1.4z\"/>\n</svg>"
        case .youtubeLogo:
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"currentColor\">\n  <path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M21.6 7.2c-.25-1-.95-1.7-1.95-1.95C17.9 4.8 12 4.8 12 4.8s-5.9 0-7.65.45c-1 .25-1.7.95-1.95 1.95C2 8.95 2 12 2 12s0 3.05.4 4.8c.25 1 .95 1.7 1.95 1.95 1.75.45 7.65.45 7.65.45s5.9 0 7.65-.45c1-.25 1.7-.95 1.95-1.95.4-1.75.4-4.8.4-4.8s0-3.05-.4-4.8zM10 15.5V8.5l6 3.5-6 3.5z\"/>\n</svg>"
        }
    }
}
