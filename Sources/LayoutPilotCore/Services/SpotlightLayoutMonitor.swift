import AppKit
import Foundation

public final class SpotlightLayoutMonitor: @unchecked Sendable {
    public static let shared = SpotlightLayoutMonitor()

    private let queue = DispatchQueue(label: "com.velizard.LayoutPilot.spotlight-layout-monitor")
    private let usInputSources = ["com.apple.keylayout.US", "com.apple.keylayout.ABC"]
    private var timer: DispatchSourceTimer?

    private init() {}

    public func start() {
        guard timer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func refresh() {
        let activeContext = SystemApplicationContexts.activeContext(frontmostApplication: nil)
        guard activeContext.bundleID == SystemApplicationContexts.spotlight.bundleID else {
            return
        }

        let client = SystemInputSourceClient()

        for sourceID in usInputSources {
            if (try? client.activateInputSource(withID: sourceID)) != nil {
                return
            }
        }
    }
}
