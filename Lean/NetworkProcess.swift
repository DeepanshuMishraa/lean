import WebKit

// WebKit's network process: one per app, behind every data store, private
// windows included. It can wedge on a host (seen on x.com after a tab was
// closed mid-reload): every later load of that host, in any tab or window,
// sits blank with the spinner running until Lean is relaunched. Ending the
// process is the relaunch's cure without the relaunch: WebKit starts a new
// one with the next load.
//
// WebKit offers this only through a name outside the public framework, so
// it is asked for before it is used; a WebKit without it leaves the reload
// as it always was.

enum NetworkProcess {
    /// Ends the network process. False when this WebKit has no way to.
    /// Loads in flight in every tab fail and need reloading.
    @MainActor
    @discardableResult
    static func restart(via dataStore: WKWebsiteDataStore) -> Bool {
        let selector = NSSelectorFromString("_terminateNetworkProcess")
        guard dataStore.responds(to: selector) else {
            NSLog("Could not restart WebKit's network process: this WebKit has no _terminateNetworkProcess. The stalled page is reloaded without it.")
            return false
        }
        dataStore.perform(selector)
        return true
    }
}
