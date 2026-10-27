import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let game = model.activeGame {
            Text("Spielt: \(game.name)")
            Button("Stoppen") { model.stop() }
        } else {
            Text("Kein Status aktiv")
        }
        Divider()
        Button("Fenster öffnen") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("PlayStatus beenden") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
