import AppKit
import Foundation
import Testing
import WebKit
@testable import Lean

/// End-to-end repro of right-click › Download Video on a <video> element:
/// builds WebKit's real context menu for a synthesized right-click and
/// performs the Download Video item, exactly as a user click dispatches it.
struct MediaMenuDownloadTests {
    @MainActor
    @Test("Menu Download Video saves the file")
    func menuDownloadVideoSavesFile() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeanMenuDL-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = Data(repeating: 0xCD, count: 128 * 1024)
        let server = try LoopbackClipServer(payload: payload, mimeType: "video/mp4", disposition: nil)
        defer { server.stop() }

        let tab = LeanTab(
            dataStore: .nonPersistent(),
            initialURL: nil,
            scrollbarStyle: .normal,
            adBlockingEnabled: false
        )
        let manager = DownloadManager(database: nil)
        manager.downloadDirectory = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: manager.downloadDirectory, withIntermediateDirectories: true)
        tab.downloadManager = manager

        // Host the web view in a real window so hit-testing works.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let webView = tab.webView
        webView.frame = window.contentView!.bounds
        webView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(webView)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        let page = """
        <html><body style="margin:0"><video id="v" width="400" height="300" src="http://127.0.0.1:\(server.port)/clip.mp4"></video></body></html>
        """
        webView.loadHTMLString(page, baseURL: nil)
        try await Self.waitUntil(ms: 10000) { webView.title != nil || webView.url != nil || webView.isLoading == false }

        // Right-click the middle of the video element.
        guard let point = await Self.videoCenter(webView) else {
            Issue.record("video element has no size yet")
            return
        }
        let viewPoint = NSPoint(x: point.x, y: point.y)
        let windowPoint = webView.convert(viewPoint, to: nil)
        let screenPoint = webView.window?.convertPoint(toScreen: windowPoint) ?? .zero
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: screenPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: webView.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            Issue.record("could not synthesize right-click")
            return
        }
        // Dispatch a real right-click: WebKit only builds its menu during
        // event dispatch. Lean's own hook captures it and cancels tracking
        // before anything shows on screen.
        let captured = CapturedMenu()
        webView.contextMenuHook = { menu in
            captured.menu = menu
            DispatchQueue.main.async { menu.cancelTracking() }
        }
        NSLog("[LeanMenuTest] click screen=%@ win=%@ bounds=%@ eventLoc=%@ winNum=%ld", NSStringFromPoint(screenPoint), NSStringFromRect(webView.window?.frame ?? .zero), NSStringFromRect(webView.bounds), NSStringFromPoint(event.locationInWindow), event.windowNumber)
        webView.rightMouseDown(with: event)
        if let direct = webView.menu(for: event) {
            NSLog("[LeanMenuTest] direct menu has %ld items: %@", direct.items.count, direct.items.map(\.title).joined(separator: " | "))
            if captured.menu == nil { captured.menu = direct }
        }
        webView.contextMenuHook = nil
        guard let menu = captured.menu else {
            Issue.record("WebKit produced no context menu")
            return
        }
        let titles = menu.items.map(\.title)
        guard let item = menu.items.first(where: {
            $0.title.localizedCaseInsensitiveContains("Download Video")
        }) else {
            Issue.record("no Download Video item; menu was: \(titles.joined(separator: " | "))")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        _ = item.target?.perform(item.action, with: item)

        var ticks = 0
        while ticks < 150 {
            if let dl = manager.downloads.first, dl.state == .completed { break }
            if let dl = manager.downloads.first, dl.state == .failed || dl.state == .cancelled {
                Issue.record("download ended \(dl.state) \(dl.errorDescription ?? "-")")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
            ticks += 1
        }
        let dl = try #require(manager.downloads.first, "no download started from the menu item")
        #expect(dl.state == .completed, "\(dl.state) \(dl.errorDescription ?? "-")")
        let size = (try? FileManager.default.attributesOfItem(atPath: dl.destinationURL.path)[.size] as? Int) ?? -1
        #expect(size == payload.count)
        window.orderOut(nil)
    }

    @MainActor
    static func videoCenter(_ webView: WKWebView) async -> CGPoint? {
        for _ in 0..<100 {
            let rect: CGRect? = await withCheckedContinuation { continuation in
                webView.evaluateJavaScript(
                    "(() => { const v = document.getElementById('v'); if (!v) return null; const r = v.getBoundingClientRect(); return [r.x, r.y, r.width, r.height]; })()"
                ) { result, _ in
                    var out: CGRect?
                    if let parts = result as? [Double], parts.count == 4, parts[2] > 10 {
                        out = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
                    }
                    continuation.resume(returning: out)
                }
            }
            if let rect, rect.width > 10 {
                // Flip to AppKit view coordinates (origin bottom-left).
                let h = webView.bounds.height
                return CGPoint(x: rect.midX, y: h - rect.midY)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    static func waitUntil(ms: Int, _ condition: @escaping @MainActor () -> Bool) async throws {
        var waited = 0
        while waited < ms {
            if await MainActor.run(resultType: Bool.self, body: condition) { return }
            try await Task.sleep(for: .milliseconds(100))
            waited += 100
        }
    }
}

/// Box for the menu captured out of `rightMouseDown` dispatch.
final class CapturedMenu: @unchecked Sendable {
    var menu: NSMenu?
    init() {}
}
final class LoopbackClipServer: Sendable {
    let port: Int
    private let listenFD: Int32
    private let payload: Data
    private let mimeType: String
    private let disposition: String?

    init(payload: Data, mimeType: String, disposition: String?) throws {
        self.payload = payload
        self.mimeType = mimeType
        self.disposition = disposition
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw NSError(domain: "LeanMenuDL", code: 2) }
        var one: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(sock, 16) == 0 else {
            close(sock)
            throw NSError(domain: "LeanMenuDL", code: 3)
        }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(sock, $0, &len) }
        }
        self.listenFD = sock
        self.port = Int(CFSwapInt16BigToHost(actual.sin_port))
        Thread.detachNewThread { [listenFD = sock, payload, mimeType, disposition] in
            Self.acceptLoop(fd: listenFD, payload: payload, mimeType: mimeType, disposition: disposition)
        }
    }

    func stop() {
        shutdown(listenFD, SHUT_RDWR)
        close(listenFD)
    }

    private static func acceptLoop(fd: Int32, payload: Data, mimeType: String, disposition: String?) {
        while true {
            var client = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let cfd = withUnsafeMutablePointer(to: &client) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(fd, $0, &len) }
            }
            if cfd < 0 { return }
            handle(client: cfd, payload: payload, mimeType: mimeType, disposition: disposition)
        }
    }

    private static func handle(client cfd: Int32, payload: Data, mimeType: String, disposition: String?) {
        defer { close(cfd) }
        var request = Data()
        var chunk = [UInt8](repeating: 0, count: 2048)
        while request.count < 65536 {
            let n = recv(cfd, &chunk, chunk.count, 0)
            if n <= 0 { return }
            request.append(contentsOf: chunk.prefix(n))
            if request.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        // Answer byte ranges (video element + download both may ask).
        let text = String(data: request, encoding: .utf8) ?? ""
        var start = 0
        var end = payload.count - 1
        var partial = false
        if let rangeLine = text.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("range:") }) {
            let spec = rangeLine.dropFirst(6).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "bytes=", with: "")
            let bounds = spec.split(separator: "-").map { Int($0) ?? 0 }
            if bounds.count == 2 {
                start = min(bounds[0], payload.count)
                end = min(bounds[1], payload.count - 1)
                partial = true
            } else if bounds.count == 1 {
                start = min(bounds[0], payload.count)
                partial = true
            }
        }
        let slice = payload[start...max(start, end)]
        var head = partial
            ? "HTTP/1.0 206 Partial Content\r\nContent-Type: \(mimeType)\r\nAccept-Ranges: bytes\r\nContent-Range: bytes \(start)-\(end)/\(payload.count)\r\nContent-Length: \(slice.count)\r\nConnection: close\r\n\r\n"
            : "HTTP/1.0 200 OK\r\nContent-Type: \(mimeType)\r\nAccept-Ranges: bytes\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        if let disposition {
            head = head.replacingOccurrences(of: "Connection: close", with: "Content-Disposition: \(disposition)\r\nConnection: close")
        }
        sendAll(cfd, Array(head.utf8))
        sendAll(cfd, Array(slice))
    }

    private static func sendAll(_ cfd: Int32, _ bytes: [UInt8]) {
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBufferPointer {
                send(cfd, $0.baseAddress! + sent, bytes.count - sent, 0)
            }
            guard n > 0 else { return }
            sent += n
        }
    }
}
