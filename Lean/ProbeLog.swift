import Foundation // DEBUGTMP
func probeLog(_ line: String) {
    let path = NSHomeDirectory() + "/lean-probe.log"
    let data = Data((String(format: "%.3f ", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) + line + "\n").utf8)
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: URL(fileURLWithPath: path)) }
}
