import AppKit
import ApplicationServices
import Darwin
import Foundation

/// The herdr pane that receives keyboard input, when the frontmost terminal window is a herdr client.
public struct TerminalPaneFocus: Equatable, Sendable {
    public var hostBundleID: String
    public var paneID: String
    /// herdr's name for the coding agent running in the pane (`omp`, `claude`, ...); `nil` for a plain shell.
    public var agent: String?

    public init(hostBundleID: String, paneID: String, agent: String?) {
        self.hostBundleID = hostBundleID
        self.paneID = paneID
        self.agent = agent
    }

    public var isAgent: Bool { agent != nil }

    /// Keeps this pane's layout memory apart from the host application and from other panes.
    public var contextKey: String { "\(hostBundleID)#herdr:\(paneID)" }
}

@MainActor
public protocol TerminalPaneFocusProviding: AnyObject {
    /// The focused herdr pane when `bundleID` is frontmost and its focused window is a herdr client.
    func terminalPaneFocus(forFrontmostBundleID bundleID: String) -> TerminalPaneFocus?
}

/// Follows which herdr pane has keyboard focus, and whether an agent runs in it.
///
/// herdr publishes pane focus and agent detection on its API socket. The subscription is a
/// blocking read on a background thread, so an idle connection costs nothing. It is opened the
/// first time a terminal's focused window is a herdr client and kept afterwards, so focus is
/// already known when the terminal comes back to the front. The pane only counts while the
/// frontmost terminal window is titled `herdr`: other windows of the same terminal are ordinary
/// terminals.
@MainActor
public final class HerdrPaneMonitor: TerminalPaneFocusProviding {
    /// Terminals that can host a herdr client window.
    nonisolated public static let hostBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]

    nonisolated public static var defaultSocketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/herdr/herdr.sock")
            .path
    }

    /// Called on the main queue after `focus` changes.
    public var onChange: ((TerminalPaneFocus?) -> Void)?
    public private(set) var focus: TerminalPaneFocus?

    private let socketPath: String
    private let windowObserver = WindowActivityObserver()
    private var trackedBundleID: String?
    private var trackedPID: pid_t?
    private var hostBundleID: String?
    private var hostWindowIsHerdr = false
    private var session = HerdrSessionState()
    private var stream: HerdrEventStream?
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?

    public init(socketPath: String = HerdrPaneMonitor.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public func terminalPaneFocus(forFrontmostBundleID bundleID: String) -> TerminalPaneFocus? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let pid = frontmost?.bundleIdentifier == bundleID ? frontmost?.processIdentifier : nil
        if trackedBundleID != bundleID || trackedPID != pid {
            retarget(bundleID: bundleID, pid: pid)
        }
        return focus?.hostBundleID == bundleID ? focus : nil
    }

    private func retarget(bundleID: String, pid: pid_t?) {
        trackedBundleID = bundleID
        trackedPID = pid
        windowObserver.stop()
        hostBundleID = nil
        hostWindowIsHerdr = false

        if Self.hostBundleIDs.contains(bundleID), let pid {
            hostBundleID = bundleID
            windowObserver.start(pid: pid) { [weak self] in
                self?.refreshHostWindow()
            }
            hostWindowIsHerdr = Self.isHerdrWindowTitle(Self.focusedWindowTitle(pid: pid))
            connectIfNeeded()
        }
        publish()
    }

    private func refreshHostWindow() {
        guard hostBundleID != nil, let trackedPID else { return }
        hostWindowIsHerdr = Self.isHerdrWindowTitle(Self.focusedWindowTitle(pid: trackedPID))
        connectIfNeeded()
        publish()
    }

    private func connectIfNeeded() {
        guard hostWindowIsHerdr, stream == nil else { return }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        let stream = HerdrEventStream(socketPath: socketPath)
        self.stream = stream
        stream.start(
            onEvent: { [weak self] event in
                self?.apply(event)
            },
            onEnd: { [weak self, weak stream] in
                guard let self, let stream, self.stream === stream else { return }
                self.streamEnded()
            }
        )
    }

    private func apply(_ event: HerdrEvent) {
        reconnectAttempt = 0
        session.apply(event)
        publish()
    }

    private func streamEnded() {
        stream = nil
        session = HerdrSessionState()
        publish()

        guard hostWindowIsHerdr else { return }
        // The window still says herdr, so the server is restarting or not up yet.
        let delay = min(2.0 * pow(2.0, Double(reconnectAttempt)), 30)
        reconnectAttempt += 1
        let workItem = DispatchWorkItem { [weak self] in
            self?.reconnectWorkItem = nil
            self?.connectIfNeeded()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func publish() {
        var updated: TerminalPaneFocus?
        if let hostBundleID, hostWindowIsHerdr, let pane = session.focusedPane {
            updated = TerminalPaneFocus(hostBundleID: hostBundleID, paneID: pane.paneID, agent: pane.agent)
        }
        guard updated != focus else { return }
        focus = updated
        // Deferred so a caller asking for focus is never re-entered from inside that call.
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(updated)
        }
    }

    nonisolated static func isHerdrWindowTitle(_ title: String?) -> Bool {
        title?.lowercased().hasPrefix("herdr") == true
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &window
        ) == .success,
            let window,
            CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        ) == .success else {
            return nil
        }
        return title as? String
    }
}

/// One fact from herdr's API socket that matters for keyboard input.
enum HerdrEvent: Equatable, Sendable {
    case paneFocused(paneID: String)
    /// `agent` is `nil` once herdr releases the pane back to its shell.
    case agentChanged(paneID: String, agent: String?)
    case paneRemoved(paneID: String)
    case panesListed([HerdrPaneSummary])
}

struct HerdrPaneSummary: Equatable, Sendable {
    var paneID: String
    var agent: String?
    var isFocused: Bool
}

/// Focused pane and running agents, reduced from herdr's events.
struct HerdrSessionState: Equatable {
    private(set) var focusedPaneID: String?
    private var agentsByPaneID: [String: String] = [:]

    var focusedPane: (paneID: String, agent: String?)? {
        focusedPaneID.map { ($0, agentsByPaneID[$0]) }
    }

    mutating func apply(_ event: HerdrEvent) {
        switch event {
        case .paneFocused(let paneID):
            focusedPaneID = paneID
        case .agentChanged(let paneID, let agent):
            agentsByPaneID[paneID] = agent
        case .paneRemoved(let paneID):
            agentsByPaneID[paneID] = nil
            if focusedPaneID == paneID {
                focusedPaneID = nil
            }
        case .panesListed(let panes):
            agentsByPaneID = [:]
            for pane in panes {
                agentsByPaneID[pane.paneID] = pane.agent
            }
            let focused = panes.filter(\.isFocused)
            if focused.count == 1 {
                focusedPaneID = focused[0].paneID
            }
        }
    }
}

/// herdr's newline-delimited JSON API.
enum HerdrProtocol {
    static let subscriptions = ["pane.focused", "pane.agent_detected", "pane.closed", "pane.exited"]

    static func subscribeRequest() -> Data {
        requestLine(
            id: "layoutpilot-events",
            method: "events.subscribe",
            params: ["subscriptions": subscriptions.map { ["type": $0] }]
        )
    }

    static func paneListRequest() -> Data {
        requestLine(id: "layoutpilot-panes", method: "pane.list", params: [:])
    }

    static func isSubscriptionStarted(_ line: Data) -> Bool {
        guard let object = jsonObject(line),
              let result = object["result"] as? [String: Any] else {
            return false
        }
        return result["type"] as? String == "subscription_started"
    }

    /// `nil` for events that do not change pane focus or agents.
    static func parseEventLine(_ line: Data) -> HerdrEvent? {
        guard let object = jsonObject(line),
              let name = object["event"] as? String,
              let data = object["data"] as? [String: Any],
              let paneID = data["pane_id"] as? String else {
            return nil
        }
        switch name {
        case "pane_focused":
            return .paneFocused(paneID: paneID)
        case "pane_agent_detected":
            let released = data["released"] as? Bool == true
            return .agentChanged(paneID: paneID, agent: released ? nil : data["agent"] as? String)
        case "pane_closed", "pane_exited":
            return .paneRemoved(paneID: paneID)
        default:
            return nil
        }
    }

    static func parsePaneList(_ line: Data) -> [HerdrPaneSummary]? {
        guard let object = jsonObject(line),
              let result = object["result"] as? [String: Any],
              let panes = result["panes"] as? [[String: Any]] else {
            return nil
        }
        return panes.compactMap { pane in
            guard let paneID = pane["pane_id"] as? String else { return nil }
            return HerdrPaneSummary(
                paneID: paneID,
                agent: pane["agent"] as? String,
                isFocused: pane["focused"] as? Bool == true
            )
        }
    }

    private static func requestLine(id: String, method: String, params: [String: Any]) -> Data {
        let request: [String: Any] = ["id": id, "method": method, "params": params]
        var data = (try? JSONSerialization.data(withJSONObject: request)) ?? Data()
        data.append(0x0A)
        return data
    }

    private static func jsonObject(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }
}

/// herdr's event subscription, read on its own thread until the socket closes. It is never torn
/// down on purpose: a blocked read costs nothing, and focus stays current while the terminal is
/// in the background.
final class HerdrEventStream: Sendable {
    private let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    /// Both callbacks run on the main queue, in order. `onEnd` runs exactly once.
    func start(
        onEvent: @escaping @MainActor (HerdrEvent) -> Void,
        onEnd: @escaping @MainActor () -> Void
    ) {
        let thread = Thread { [self] in
            run(
                deliver: { event in
                    DispatchQueue.main.async { MainActor.assumeIsolated { onEvent(event) } }
                }
            )
            DispatchQueue.main.async { MainActor.assumeIsolated { onEnd() } }
        }
        thread.name = "com.velizard.LayoutPilot.herdr-events"
        thread.qualityOfService = .utility
        thread.start()
    }

    private func run(deliver: (HerdrEvent) -> Void) {
        guard let socket = HerdrSocket.connect(path: socketPath) else { return }
        defer { close(socket) }

        guard HerdrSocket.writeAll(socket, HerdrProtocol.subscribeRequest()) else { return }
        var reader = HerdrLineReader(socket: socket)
        guard let acknowledgement = reader.nextLine(),
              HerdrProtocol.isSubscriptionStarted(acknowledgement) else {
            return
        }
        // Subscribing first means nothing that happens while the list is fetched is missed.
        if let response = HerdrSocket.request(path: socketPath, HerdrProtocol.paneListRequest()),
           let panes = HerdrProtocol.parsePaneList(response) {
            deliver(.panesListed(panes))
        }
        while let line = reader.nextLine() {
            if let event = HerdrProtocol.parseEventLine(line) {
                deliver(event)
            }
        }
    }
}

struct HerdrLineReader {
    let socket: Int32
    private var buffer = Data()
    private var chunk = [UInt8](repeating: 0, count: 16 * 1024)

    init(socket: Int32) {
        self.socket = socket
    }

    /// The next line without its terminator, or `nil` once the socket closes.
    mutating func nextLine() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return Data(line)
            }
            let count = chunk.withUnsafeMutableBytes { bytes in
                read(socket, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                buffer.append(contentsOf: chunk[0..<count])
            } else if count < 0, errno == EINTR {
                continue
            } else {
                return nil
            }
        }
    }
}

enum HerdrSocket {
    static func connect(path: String, receiveTimeout: TimeInterval? = nil) -> Int32? {
        var address = sockaddr_un()
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }

        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }

        var noSigPipe: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        if let receiveTimeout {
            var timeout = timeval(
                tv_sec: Int(receiveTimeout),
                tv_usec: Int32((receiveTimeout - floor(receiveTimeout)) * 1_000_000)
            )
            setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        }

        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.connect(socket, address, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(socket)
            return nil
        }
        return socket
    }

    static func writeAll(_ socket: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(socket, bytes.baseAddress! + offset, bytes.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    /// One request on its own connection; `nil` on any failure or after two seconds.
    static func request(path: String, _ payload: Data) -> Data? {
        guard let socket = connect(path: path, receiveTimeout: 2) else { return nil }
        defer { close(socket) }
        guard writeAll(socket, payload) else { return nil }
        var reader = HerdrLineReader(socket: socket)
        return reader.nextLine()
    }
}
