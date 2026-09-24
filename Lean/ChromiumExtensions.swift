import Foundation

// Finding the extensions another Chromium browser holds.
//
// Every Chromium browser keeps unpacked extensions per profile under
// `<profile>/Extensions/<32-char id>/<version>/manifest.json`. Lean runs
// each one through its normal permission review before it can run, so the
// scan only finds them — nothing here enables anything.
//
// Enabled state is deliberately not read: newer Chromium keeps it in
// runtime-flavoured fields (`active_bit`, `disable_reasons`) that say
// whether the extension is loaded right now, not whether the person wants
// it. The review sheet is the consent.
struct FoundExtension: Identifiable, Equatable {
    /// The Chrome Web Store id — doubles as Lean's installation id.
    let id: String
    let name: String
    let version: String
    /// The version directory holding manifest.json.
    let path: URL
}

enum ChromiumExtensions {
    /// Every extension under a granted browser data folder, across all its
    /// profiles. Highest version wins when profiles disagree.
    static func scan(in directory: URL) -> [FoundExtension] {
        var byID: [String: FoundExtension] = [:]
        for extensionsDir in extensionRoots(in: directory) {
            for id in (try? FileManager.default.contentsOfDirectory(atPath: extensionsDir.path)) ?? [] {
                guard id.count == 32, id.allSatisfy(\.isHexDigit) else { continue }
                let idDir = extensionsDir.appendingPathComponent(id, isDirectory: true)
                guard let found = newest(in: idDir, id: id) else { continue }
                if let current = byID[id] {
                    guard compareVersions(found.version, current.version) == .orderedDescending else { continue }
                }
                byID[id] = found
            }
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - discovery

    private static func extensionRoots(in directory: URL) -> [URL] {
        // The granted folder is usually the data root holding profiles, but
        // it may itself be a profile (or a User Data dir one level down).
        var roots: [URL] = []
        guard let walk = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        for case let url as URL in walk {
            guard url.lastPathComponent == "Extensions" else { continue }
            let depth = url.pathComponents.count - directory.pathComponents.count
            if depth > 4 {
                walk.skipDescendants()
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { continue }
            roots.append(url)
            walk.skipDescendants()
        }
        return roots
    }

    private static func newest(in idDir: URL, id: String) -> FoundExtension? {
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: idDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return nil }
        let candidates = versions.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                && FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path)
        }
        guard let best = candidates.sorted(by: { compareVersions($0.lastPathComponent, $1.lastPathComponent) == .orderedDescending }).first,
              let (name, version) = manifestNameAndVersion(in: best)
        else { return nil }
        return FoundExtension(id: id, name: name, version: version, path: best)
    }

    // MARK: - manifest

    private static func manifestNameAndVersion(in versionDir: URL) -> (String, String)? {
        let url = versionDir.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let version = (manifest["version"] as? String) ?? versionDir.lastPathComponent
        var name = (manifest["name"] as? String) ?? versionDir.deletingLastPathComponent().lastPathComponent
        if name.hasPrefix("__MSG_"), name.hasSuffix("__") {
            let key = String(name.dropFirst(6).dropLast(2))
            name = localizedMessage(key, in: versionDir) ?? name
        }
        return (name, version)
    }

    private static func localizedMessage(_ key: String, in versionDir: URL) -> String? {
        let locales = versionDir.appendingPathComponent("_locales", isDirectory: true)
        let preferred = ["en", "en_US", "en_GB"]
        var candidates = preferred.map { locales.appendingPathComponent($0, isDirectory: true) }
        if let others = try? FileManager.default.contentsOfDirectory(at: locales, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            candidates += others.filter { !preferred.contains($0.lastPathComponent) }
        }
        for dir in candidates {
            let file = dir.appendingPathComponent("messages.json")
            guard let data = try? Data(contentsOf: file),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = (messages[key] as? [String: Any])?["message"] as? String,
                  !message.isEmpty
            else { continue }
            return message
        }
        return nil
    }

    // MARK: - versions

    /// Numeric dot-separated compare ("7.0.6" > "7.0.6_0"? No: trailing
    /// junk compares after the numbers, so "7.0.6_0" wins — which is what we
    /// want: the suffixed dir is the newer install).
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let split: (String) -> [String] = { $0.split { !$0.isNumber }.map(String.init) }
        let left = split(lhs), right = split(rhs)
        for (l, r) in zip(left, right) {
            if let li = Int(l), let ri = Int(r) {
                if li != ri { return li < ri ? .orderedAscending : .orderedDescending }
            } else if l != r {
                return l.compare(r) == .orderedAscending ? .orderedAscending : .orderedDescending
            }
        }
        if left.count != right.count { return left.count < right.count ? .orderedAscending : .orderedDescending }
        if lhs != rhs { return lhs.compare(rhs) == .orderedAscending ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}
