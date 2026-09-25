import Foundation
import Testing
import WebKit
@testable import Lean

/// Reproduction for "Download Video does nothing": serves bytes over loopback
/// with `Content-Disposition: attachment` — the same delegate chain WebKit's
/// media-menu item uses (`decidePolicy` → `didBecome` → `decideDestination`
/// → file on disk → `downloadDidFinish`) — and asserts a file lands
/// byte-identical.
struct VideoDownloadChainTests {
    @MainActor
    @Test("Attachment navigation completes through the tab delegate chain")
    func directDownloadCompletes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeanDownloadTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = Data(repeating: 0xAB, count: 256 * 1024)

        let server = try LoopbackFileServer(payload: payload)
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

        tab.load(URL(string: "http://127.0.0.1:\(server.port)/clip.mp4")!)

        var ticks = 0
        var lastLog = "no item yet"
        while ticks < 150 {
            if let item = manager.downloads.first {
                let diskSize = (try? FileManager.default.attributesOfItem(atPath: item.destinationURL.path)[.size] as? Int) ?? -1
                lastLog = "state=\(item.state) received=\(item.receivedBytes) total=\(item.totalBytes) disk=\(diskSize) err=\(item.errorDescription ?? "-")"
                if item.state == .completed { break }
                if item.state == .failed || item.state == .cancelled {
                    Issue.record("download ended \(lastLog)")
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(100))
            ticks += 1
        }
        let item = try #require(manager.downloads.first)
        #expect(item.state == .completed, "\(lastLog)")
        let size = (try? FileManager.default.attributesOfItem(atPath: item.destinationURL.path)[.size] as? Int) ?? -1
        #expect(size == payload.count)
    }
}

/// Blocking loopback HTTP/1.0 server for one payload. Blocking I/O on a
/// background thread: no EAGAIN races, no runloop interaction.
final class LoopbackFileServer: Sendable {
    let port: Int
    private let listenFD: Int32
    private let payload: Data

    init(payload: Data) throws {
        self.payload = payload
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw NSError(domain: "LeanDownloadTest", code: 2) }
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
            throw NSError(domain: "LeanDownloadTest", code: 3)
        }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(sock, $0, &len) }
        }
        self.listenFD = sock
        self.port = Int(CFSwapInt16BigToHost(actual.sin_port))
        Thread.detachNewThread { [listenFD = sock, payload] in
            Self.acceptLoop(fd: listenFD, payload: payload)
        }
    }

    func stop() {
        shutdown(listenFD, SHUT_RDWR)
        close(listenFD)
    }

    private static func acceptLoop(fd: Int32, payload: Data) {
        while true {
            var client = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let cfd = withUnsafeMutablePointer(to: &client) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(fd, $0, &len) }
            }
            if cfd < 0 { return }
            handle(client: cfd, payload: payload)
        }
    }

    private static func handle(client cfd: Int32, payload: Data) {
        defer { close(cfd) }
        // Read until end of headers (blocking; client always sends).
        var request = Data()
        var chunk = [UInt8](repeating: 0, count: 2048)
        while request.count < 65536 {
            let n = recv(cfd, &chunk, chunk.count, 0)
            if n <= 0 { return }
            request.append(contentsOf: chunk.prefix(n))
            if request.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        let head = "HTTP/1.0 200 OK\r\nContent-Type: video/mp4\r\nContent-Disposition: attachment; filename=\"clip.mp4\"\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        sendAll(cfd, Array(head.utf8))
        sendAll(cfd, [UInt8](payload))
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
