import Foundation
import Testing
import WebKit
@testable import Lean

struct WebExtensionPrototypeTests {
    @Test("Chrome Web Store URLs resolve only on supported store domains")
    func chromeWebStoreAddressParsing() {
        let id = "abcdefghijklmnopabcdefghijklmnop"
        #expect(ChromeWebStoreInstaller.extensionID(from: id) == id)
        #expect(ChromeWebStoreInstaller.extensionID(from: "https://chromewebstore.google.com/detail/name/\(id)") == id)
        #expect(ChromeWebStoreInstaller.extensionID(from: "https://chrome.google.com/webstore/detail/name/\(id)") == id)
        #expect(ChromeWebStoreInstaller.extensionID(from: "https://evil.example/\(id)") == nil)
        #expect(ChromeWebStoreInstaller.extensionID(from: "not-an-extension-id") == nil)
        #expect(throws: ChromeWebStoreInstaller.InstallError.invalidPackage) {
            try ChromeWebStoreInstaller.unpack(Data("invalid".utf8), expectedID: id, to: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        }
    }

    @available(macOS 15.4, *)
    @MainActor
    @Test("WebKit loads, disables, reloads, and revokes a local extension")
    func localExtensionLifecycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeanExtensionPrototype-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = """
        {"manifest_version":3,"name":"Lean Prototype","version":"1.0","description":"Local lifecycle test","permissions":["storage"]}
        """
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("manifest.json"))

        let extensionModel = try await WKWebExtension(resourceBaseURL: directory)
        #expect(extensionModel.errors.isEmpty)
        #expect(extensionModel.requestedPermissions.contains(.storage))

        let context = WKWebExtensionContext(for: extensionModel)
        let controller = WKWebExtensionController()
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.webExtensionController = controller
        #expect(webViewConfiguration.webExtensionController === controller)

        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        #expect(context.permissionStatus(for: .storage) == .grantedExplicitly)

        try controller.load(context)
        #expect(context.isLoaded)
        try controller.unload(context)
        #expect(!context.isLoaded)

        try controller.load(context)
        #expect(context.isLoaded)
        try controller.unload(context)
        context.setPermissionStatus(.deniedExplicitly, for: .storage)
        #expect(context.permissionStatus(for: .storage) == .deniedExplicitly)
    }
}
