import Foundation
import Testing
import WebKit
@testable import Lean

struct NativeMessagingGrantTests {
    @Test("Required native messaging is granted on load")
    func requiredGranted() {
        guard #available(macOS 15.4, *) else { return }
        let key = WKWebExtension.Permission.nativeMessaging.rawValue
        let resolved = BrowserExtensionManager.resolvedLoadPermissions(
            requiredValues: [key, "tabs"],
            grantedValues: ["tabs"]
        )
        #expect(resolved.contains(key))
        #expect(resolved.contains("tabs"))
    }

    @Test("Already-granted permission is left alone")
    func alreadyGrantedUnchanged() {
        guard #available(macOS 15.4, *) else { return }
        let key = WKWebExtension.Permission.nativeMessaging.rawValue
        let resolved = BrowserExtensionManager.resolvedLoadPermissions(
            requiredValues: [key],
            grantedValues: [key]
        )
        #expect(resolved == [key])
    }

    @Test("Unrequested permission is never added")
    func unrequestedUnchanged() {
        guard #available(macOS 15.4, *) else { return }
        let key = WKWebExtension.Permission.nativeMessaging.rawValue
        let resolved = BrowserExtensionManager.resolvedLoadPermissions(
            requiredValues: ["tabs"],
            grantedValues: ["tabs"]
        )
        #expect(!resolved.contains(key))
        #expect(resolved == ["tabs"])
    }

    @Test("Optional-only native messaging still needs an explicit grant")
    func optionalNeedsExplicitGrant() {
        guard #available(macOS 15.4, *) else { return }
        let key = WKWebExtension.Permission.nativeMessaging.rawValue
        // Optional permissions are not in `requiredValues`: the user must
        // tick them in the install review or settings first.
        let resolved = BrowserExtensionManager.resolvedLoadPermissions(
            requiredValues: [],
            grantedValues: []
        )
        #expect(!resolved.contains(key))
    }
}
