import AppKit
import LayoutPilotCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UpdaterService.shared.start()

        // The learning store batches its writes behind a long debounce, so the moments where
        // the process is about to stop running have to force a flush.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            SmartInputLearningStore.shared.flushSynchronously()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SmartInputLearningStore.shared.flushSynchronously()
    }
}
