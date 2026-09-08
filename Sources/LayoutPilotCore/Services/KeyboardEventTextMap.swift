import Carbon
import CoreGraphics
import Foundation

/// Immutable physical-key translation, built off the Event Tap thread. Session-tap
/// Unicode can retain the previous layout after TISSelectInputSource succeeds.
struct KeyboardEventTextMap: Sendable, Equatable {
    let sourceID: String
    private let characters: [Int: String]

    static func load(sourceID: String) -> KeyboardEventTextMap? {
        precondition(Thread.isMainThread)
        // Only direct layouts supported by Smart Input; never reinterpret IME text.
        guard ["com.apple.keylayout.US", "com.apple.keylayout.ABC",
               "com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin"].contains(sourceID),
              let list = TISCreateInputSourceList(
                [kTISPropertyInputSourceID as String: sourceID] as CFDictionary, false
              )?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var characters: [Int: String] = [:]
        for modifiers in 0..<4 {
            let carbonFlags = (modifiers & 1 != 0 ? shiftKey : 0)
                | (modifiers & 2 != 0 ? alphaLock : 0)
            for key in 0..<128 {
                var deadKey: UInt32 = 0
                var length = 0
                var output = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, UInt16(key), UInt16(kUCKeyActionDown),
                    UInt32(carbonFlags >> 8), UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKey,
                    output.count, &length, &output)
                if status == noErr, length > 0 {
                    characters[key + modifiers * 128] = String(utf16CodeUnits: output, count: length)
                }
            }
        }
        return KeyboardEventTextMap(sourceID: sourceID, characters: characters)
    }

    func text(keyCode: Int64, flags: CGEventFlags, fallback: String?) -> String? {
        guard (0..<128).contains(keyCode),
              !flags.contains(.maskCommand), !flags.contains(.maskControl),
              !flags.contains(.maskAlternate), fallback?.count == 1 else { return fallback }
        let modifiers = (flags.contains(.maskShift) ? 1 : 0)
            | (flags.contains(.maskAlphaShift) ? 2 : 0)
        return characters[Int(keyCode) + modifiers * 128] ?? fallback
    }
}
