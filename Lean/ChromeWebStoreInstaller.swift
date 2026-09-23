import CryptoKit
import Foundation
import Security

/// Downloads and verifies Chrome Web Store CRX3 packages before unpacking them.
enum ChromeWebStoreInstaller {
    enum InstallError: LocalizedError, Equatable {
        case invalidAddress
        case alreadyInstalled
        case badResponse
        case invalidPackage
        case invalidSignature
        case unpackFailed

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "Enter a Chrome Web Store link or a valid extension ID."
            case .alreadyInstalled: "That extension is already installed."
            case .badResponse: "The Chrome Web Store download failed. Check the link and try again."
            case .invalidPackage: "The Chrome Web Store returned an invalid extension package."
            case .invalidSignature: "The extension signature could not be verified."
            case .unpackFailed: "The extension package could not be unpacked."
            }
        }
    }

    static func extensionID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isExtensionID(text) { return text }
        let address = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: address),
              let host = url.host?.lowercased(),
              host == "chromewebstore.google.com" || host == "chrome.google.com",
              host != "chrome.google.com" || url.path.hasPrefix("/webstore") else { return nil }
        return url.pathComponents.last(where: isExtensionID)
    }

    static func fetch(_ id: String) async throws -> Data {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")
        components?.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: "140.0.0.0"),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&installsource=ondemand&uc")
        ]
        guard let url = components?.url else { throw InstallError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), !data.isEmpty else {
            throw InstallError.badResponse
        }
        return data
    }

    static func unpack(_ package: Data, expectedID: String, to destination: URL) throws {
        let bytes = [UInt8](package)
        guard bytes.count > 12, Array(bytes.prefix(4)) == Array("Cr24".utf8), littleEndian32(bytes, 4) == 3 else {
            throw InstallError.invalidPackage
        }
        let headerLength = Int(littleEndian32(bytes, 8))
        guard headerLength <= bytes.count - 12 else { throw InstallError.invalidPackage }
        let header = Array(bytes[12..<(12 + headerLength)])
        let zip = Data(bytes[(12 + headerLength)...])
        let fields = protobufFields(header)
        guard let signedHeader = fields.first(where: { $0.number == 10000 })?.bytes,
              let signedID = protobufFields(signedHeader).first(where: { $0.number == 1 })?.bytes,
              extensionID(for: signedID) == expectedID else { throw InstallError.invalidSignature }

        var signedMessage = Data("CRX3 SignedData".utf8)
        signedMessage.append(0)
        var length = UInt32(signedHeader.count).littleEndian
        withUnsafeBytes(of: &length) { signedMessage.append(contentsOf: $0) }
        signedMessage.append(contentsOf: signedHeader)
        signedMessage.append(zip)

        let hasValidSignature = fields.filter { $0.number == 2 }.contains { field in
            let proof = protobufFields(field.bytes)
            guard let publicKey = proof.first(where: { $0.number == 1 })?.bytes,
                  let signature = proof.first(where: { $0.number == 2 })?.bytes,
                  extensionID(for: Array(SHA256.hash(data: Data(publicKey)).prefix(16))) == expectedID,
                  let key = importPublicKey(publicKey) else { return false }
            return SecKeyVerifySignature(
                key,
                .rsaSignatureMessagePKCS1v15SHA256,
                signedMessage as CFData,
                Data(signature) as CFData,
                nil
            )
        }
        guard hasValidSignature else { throw InstallError.invalidSignature }

        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory.appendingPathComponent("Lean-crx-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let archive = scratch.appendingPathComponent("extension.zip")
        let output = scratch.appendingPathComponent("contents", isDirectory: true)
        try zip.write(to: archive)
        let unpacker = Process()
        unpacker.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unpacker.arguments = ["-x", "-k", archive.path, output.path]
        do { try unpacker.run() } catch { throw InstallError.unpackFailed }
        unpacker.waitUntilExit()
        guard unpacker.terminationStatus == 0,
              fileManager.fileExists(atPath: output.appendingPathComponent("manifest.json").path) else {
            throw InstallError.unpackFailed
        }
        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: output, to: destination)
    }

    private static func isExtensionID(_ text: String) -> Bool {
        text.utf8.count == 32 && text.utf8.allSatisfy { (97...112).contains($0) }
    }

    private static func extensionID(for bytes: [UInt8]) -> String {
        String(decoding: bytes.flatMap { [UInt8(97) + ($0 >> 4), UInt8(97) + ($0 & 0x0f)] }, as: UTF8.self)
    }

    private static func littleEndian32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private struct Field {
        let number: Int
        let bytes: [UInt8]
    }

    private static func protobufFields(_ bytes: [UInt8]) -> [Field] {
        var offset = 0
        var fields: [Field] = []
        while offset < bytes.count {
            guard let key = varint(bytes, offset: &offset), key >> 3 > 0 else { return [] }
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard varint(bytes, offset: &offset) != nil else { return [] }
            case 1:
                guard offset <= bytes.count - 8 else { return [] }
                offset += 8
            case 2:
                guard let rawLength = varint(bytes, offset: &offset), rawLength <= UInt64(bytes.count - offset) else { return [] }
                let length = Int(rawLength)
                fields.append(Field(number: number, bytes: Array(bytes[offset..<(offset + length)])))
                offset += length
            case 5:
                guard offset <= bytes.count - 4 else { return [] }
                offset += 4
            default:
                return []
            }
        }
        return fields
    }

    private static func varint(_ bytes: [UInt8], offset: inout Int) -> UInt64? {
        var value: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard offset < bytes.count else { return nil }
            let byte = bytes[offset]
            offset += 1
            if shift == 63 && byte > 1 { return nil }
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }

    private static func importPublicKey(_ data: [UInt8]) -> SecKey? {
        var format = SecExternalFormat.formatOpenSSL
        var type = SecExternalItemType.itemTypePublicKey
        var items: CFArray?
        guard SecItemImport(Data(data) as CFData, nil, &format, &type, [], nil, nil, &items) == errSecSuccess,
              let key = (items as? [SecKey])?.first else { return nil }
        return key
    }
}
