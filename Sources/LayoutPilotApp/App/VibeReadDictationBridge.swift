import AppKit
import Darwin
import Foundation
import LayoutPilotCore

enum VibeReadDictationBridge {
    private static let appURL = URL(fileURLWithPath: "/Applications/Vibe Read.app")
    private static var listenFD: Int32 = -1

    static var controlSocketPath: String {
        "/tmp/layoutpilot-control-\(getuid()).sock"
    }

    static func startServer() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard listenFD < 0 else { return }
            let socketPath = controlSocketPath
            unlink(socketPath)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let rc: Int32 = socketPath.withCString { cstr in
                withUnsafeMutablePointer(to: &addr) { ptr in
                    let sunPath = UnsafeMutableRawPointer(ptr)
                        .advanced(by: MemoryLayout.offset(of: \sockaddr_un.sun_path) ?? 2)
                    _ = strcpy(sunPath.assumingMemoryBound(to: CChar.self), cstr)
                    return ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
            }
            guard rc == 0, listen(fd, 8) == 0 else {
                Darwin.close(fd)
                return
            }
            chmod(socketPath, 0o600)
            listenFD = fd
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { continue }
                var buffer = Data()
                var byte = [UInt8](repeating: 0, count: 1)
                while buffer.count < 64 {
                    let n = read(client, &byte, 1)
                    if n <= 0 || byte[0] == 10 { break }
                    buffer.append(byte[0])
                }
                let line = String(data: buffer, encoding: .utf8) ?? ""
                if line == "paste" {
                    DispatchQueue.main.async {
                        AXFocusInspector.pressCommandV()
                    }
                    let resp = "ok\n"
                    let data = Data(resp.utf8)
                    _ = data.withUnsafeBytes { Darwin.write(client, $0.baseAddress, data.count) }
                } else if line == "ping" {
                    let resp = "ok\n"
                    let data = Data(resp.utf8)
                    _ = data.withUnsafeBytes { Darwin.write(client, $0.baseAddress, data.count) }
                }
                Darwin.close(client)
            }
        }
    }

    static func launchIfNeeded() {
        guard FileManager.default.fileExists(atPath: appURL.path) else { return }
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: "SummerEngine.Vibe-Read"
        )
        guard running.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
    }

    static func send(_ command: DictationCommand) {
        let line: String
        switch command {
        case .holdStart: line = "hold-start"
        case .holdStop: line = "hold-stop"
        case .toggle: line = "toggle"
        }
        if write(line) { return }
        launchIfNeeded()
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline {
                if write(line) { return }
                Thread.sleep(forTimeInterval: 0.12)
            }
            NSLog("Vibe Read did not accept dictation command \(line)")
        }
    }

    private static func write(_ line: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = "/tmp/viberead-control-\(getuid()).sock"
        let rc: Int32 = path.withCString { cstr in
            withUnsafeMutablePointer(to: &addr) { ptr in
                let sunPath = UnsafeMutableRawPointer(ptr)
                    .advanced(by: MemoryLayout.offset(of: \sockaddr_un.sun_path) ?? 2)
                _ = strcpy(sunPath.assumingMemoryBound(to: CChar.self), cstr)
                return ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        guard rc == 0 else { return false }
        let data = Data((line + "\n").utf8)
        let written = data.withUnsafeBytes { buffer in
            Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
        return written == data.count
    }
}
