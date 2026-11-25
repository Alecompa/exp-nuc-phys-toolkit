#if DEBUG
import AppKit
import Foundation

/// Screenshot automation for development: with GAMOW_SNAPSHOT=<name> the app captures its window GAMOW_SNAPSHOT_DELAY seconds (default 4) and quits. Needs no
/// screen-recording permission because the app draws its own window. The PNG is printed as base64.
enum DebugSnapshot {
    @MainActor static func scheduleIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let name = env["GAMOW_SNAPSHOT"] else { return }
        let delay = Double(env["GAMOW_SNAPSHOT_DELAY"] ?? "") ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            // The sandbox container is private to the app, so the image goes to standard output (base64).
            if let png = rep.representation(using: .png, properties: [:]) {
                print("SNAPSHOT-BEGIN \(name)\n\(png.base64EncodedString())\nSNAPSHOT-END")
                fflush(stdout)
            }
            if env["GAMOW_SNAPSHOT_KEEP"] != "1" { NSApp.terminate(nil) }
        }
    }
}
#endif
