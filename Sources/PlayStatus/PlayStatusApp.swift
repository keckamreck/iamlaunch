import AppKit
import SwiftUI

@main
struct PlayStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("PlayStatus", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 480, height: 640)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.activeGame == nil ? "gamecontroller" : "gamecontroller.fill")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also show a Dock icon when started with `swift run`, outside an app bundle.
        NSApp.setActivationPolicy(.regular)
    }

    // Discord only shows the status while this app runs, so closing the
    // window keeps it running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}
