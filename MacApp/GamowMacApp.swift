import SwiftUI
import ToolkitUI

@main
struct GamowMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacRootView()
                .frame(minWidth: 900, minHeight: 600)
                #if DEBUG
                .onAppear { DebugSnapshot.scheduleIfRequested() }
                #endif
        }
        .defaultSize(width: 1280, height: 840)
        .commands { GamowMacCommands() }

        Settings {
            MacSettingsView()
        }
    }
}
