import SwiftUI
import ToolkitUI

@main
struct GamowMacApp: App {
    /// One shared setup for the window and the Settings scene.
    @State private var workbench = Workbench()

    var body: some Scene {
        WindowGroup {
            MacRootView(workbench: workbench)
                .frame(minWidth: 1080, minHeight: 640)
                #if DEBUG
                .onAppear { DebugSnapshot.scheduleIfRequested() }
                #endif
        }
        .defaultSize(width: 1280, height: 840)
        .commands { GamowMacCommands() }

        Settings {
            MacSettingsView(workbench: workbench)
        }
    }
}
