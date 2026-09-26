import Foundation

// XPC service entry point: vends NativeHostRunner to Lean over the
// LeanNativeHostServiceProtocol, and takes callbacks on the app's
// LeanNativeHostClientProtocol.

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let runner = NativeHostRunner()
        newConnection.exportedInterface = NSXPCInterface(with: LeanNativeHostServiceProtocol.self)
        newConnection.exportedObject = runner
        newConnection.remoteObjectInterface = NSXPCInterface(with: LeanNativeHostClientProtocol.self)
        runner.connection = newConnection
        // The app going away orphaned every helper: stop them instead of
        // leaving prompts open behind the browser.
        newConnection.invalidationHandler = { [weak runner] in _ = runner?.connectionGone() }
        newConnection.interruptionHandler = { [weak runner] in _ = runner?.connectionGone() }
        newConnection.resume()
        return true
    }
}

// Retained for the life of the process: the listener only holds it weakly.
let serviceDelegate = ServiceDelegate()
let serviceListener = NSXPCListener.service()
serviceListener.delegate = serviceDelegate
serviceListener.resume()
dispatchMain()
