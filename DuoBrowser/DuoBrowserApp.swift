import SwiftUI

@main
struct DuoBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--browser-checks") {
                NativeBrowserChecks().ignoresSafeArea(.container).statusBarHidden(true)
            } else { BrowserView() }
            #else
            BrowserView()
            #endif
        }
    }
}
