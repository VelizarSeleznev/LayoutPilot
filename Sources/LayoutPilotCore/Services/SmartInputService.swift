import AppKit
import Carbon
import CoreGraphics
import Foundation

public final class SmartInputService: @unchecked Sendable {
    public static let shared = SmartInputService()
    
    private let magicEventTag: Int64 = 0x44414E495348 // "DANISH"
    private let usInputSources = Set(["com.apple.keylayout.US", "com.apple.keylayout.ABC"])
    private let danishLanguage = "da"
    
    private let excludedBundleIDs = Set([
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.celeste",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ])
    
    private let triggerMap: [Character: Character] = [
        ";": "æ",
        "'": "ø",
        "‘": "ø",
        "’": "ø",
        "[": "å",
        ":": "Æ",
        "\"": "Ø",
        "{": "Å",
    ]
    
    private let uppercaseTriggers = Set<Character>([":", "\"", "{"])
    
    private final class WordBuffer {
        var token = ""
        func append(_ text: String) {
            token += text
        }
        func reset() {
            token = ""
        }
    }
    
    private let buffer = WordBuffer()
    private let checker = NSSpellChecker.shared
    
    private let lock = NSLock()
    private var _isEnabled = true
    
    public var isEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _isEnabled
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _isEnabled = newValue
        }
    }

    private var _allowedBundleIDs = Set<String>()
    
    public var allowedBundleIDs: Set<String> {
        get {
            lock.lock(); defer { lock.unlock() }
            return _allowedBundleIDs
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _allowedBundleIDs = newValue
        }
    }

    private var _translationEnabled = true
    private var _translationEndpointURL = "http://127.0.0.1:1234/v1"
    private var _translationModel = "google/gemma-4-e4b"
    private var _translationLanguages: [TranslationLanguage] = []

    public var translationEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _translationEnabled
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _translationEnabled = newValue
        }
    }

    public var translationEndpointURL: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _translationEndpointURL
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _translationEndpointURL = newValue
        }
    }

    public var translationModel: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _translationModel
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _translationModel = newValue
        }
    }

    public var translationLanguages: [TranslationLanguage] {
        get {
            lock.lock(); defer { lock.unlock() }
            return _translationLanguages
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _translationLanguages = newValue
        }
    }

    private var _smartBilingualEnabled = true
    private var _smartBilingualAllowedBundleIDs = Set<String>()

    public var smartBilingualEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _smartBilingualEnabled
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _smartBilingualEnabled = newValue
        }
    }

    public var smartBilingualAllowedBundleIDs: Set<String> {
        get {
            lock.lock(); defer { lock.unlock() }
            return _smartBilingualAllowedBundleIDs
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _smartBilingualAllowedBundleIDs = newValue
        }
    }
    
    private var eventTap: CFMachPort?
    private var isStarted = false
    
    public init() {}
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        requestAccessibilityPermissionIfNeeded()
        
        Thread.detachNewThread { [weak self] in
            self?.runEventLoop()
        }
    }
    
    private func runEventLoop() {
        let port = CFRunLoopGetCurrent()
        
        while isStarted {
            if !AXIsProcessTrusted() {
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            
            let callback: CGEventTapCallBack = { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let service = Unmanaged<SmartInputService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleEvent(type: type, event: event)
            }
            
            let selfOpaque = Unmanaged.passUnretained(self).toOpaque()
            
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                callback: callback,
                userInfo: selfOpaque
            ) else {
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            
            self.eventTap = tap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(port, runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            
            CFRunLoopRun()
        }
    }
    
    private func requestAccessibilityPermissionIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        if event.getIntegerValueField(.eventSourceUserData) == magicEventTag {
            return Unmanaged.passUnretained(event)
        }

        // Intercept global translation shortcuts
        if translationEnabled {
            let flags = event.flags
            let hasOption = flags.contains(.maskAlternate)
            let hasShift = flags.contains(.maskShift)
            let hasCommand = flags.contains(.maskCommand)
            let hasControl = flags.contains(.maskControl)
            
            if hasOption && hasShift && !hasCommand && !hasControl {
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                if let match = translationLanguages.first(where: { $0.isEnabled && $0.keyCode == keyCode }) {
                    TranslationService.shared.translateSelectedText(
                        to: match.name,
                        endpointURL: translationEndpointURL,
                        model: translationModel
                    )
                    return nil // Swallow event!
                }
            }
        }

        guard isEnabled else {
            buffer.reset()
            return Unmanaged.passUnretained(event)
        }
        
        guard shouldHandleCurrentContext() else {
            buffer.reset()
            return Unmanaged.passUnretained(event)
        }
        
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            buffer.reset()
            return Unmanaged.passUnretained(event)
        }
        
        guard let text = eventText(event), text.count == 1 else {
            return Unmanaged.passUnretained(event)
        }
        
        if isBoundary(text) {
            let activeBundleID = frontmostBundleID() ?? ""
            let isDanishAllowed = allowedBundleIDs.contains(activeBundleID)
            let isBilingualAllowed = smartBilingualAllowedBundleIDs.contains(activeBundleID)
            
            if isDanishAllowed,
               let sourceID = currentInputSourceID(),
               usInputSources.contains(sourceID),
               let replacement = replacementForCurrentToken() {
                replaceToken(with: replacement, boundary: text)
                return nil
            }
            
            if smartBilingualEnabled,
               isBilingualAllowed,
               let bilingualResult = checkBilingualConversion(for: buffer.token) {
                replaceToken(with: bilingualResult.replacement, boundary: text)
                if let targetLayoutID = bilingualResult.targetLayoutID {
                    DispatchQueue.main.async {
                        try? SystemInputSourceClient().activateInputSource(withID: targetLayoutID)
                    }
                }
                return nil
            }
            
            buffer.reset()
            return Unmanaged.passUnretained(event)
        }
        
        if let character = text.first, isWordCharacter(character) {
            buffer.append(text)
            
            let activeBundleID = frontmostBundleID() ?? ""
            let isDanishAllowed = allowedBundleIDs.contains(activeBundleID)
            
            if isDanishAllowed,
               let sourceID = currentInputSourceID(),
               usInputSources.contains(sourceID),
               (triggerMap.keys.contains(character) || startsWithTrigger(buffer.token)),
               let replacement = replacementForCurrentToken() {
                replacePendingToken(with: replacement)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        
        buffer.reset()
        return Unmanaged.passUnretained(event)
    }
    
    private func currentInputSourceID() -> String? {
        if Thread.isMainThread {
            return currentInputSourceIDOnMainThread()
        }

        return DispatchQueue.main.sync {
            currentInputSourceIDOnMainThread()
        }
    }

    private func currentInputSourceIDOnMainThread() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let rawID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(rawID).takeUnretainedValue() as String
    }
    
    private func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    
    private func shouldHandleCurrentContext() -> Bool {
        guard let sourceID = currentInputSourceID() else {
            return false
        }
        
        let isRussian = sourceID.localizedCaseInsensitiveContains("Russian") || 
                        sourceID.hasSuffix(".ru") || 
                        sourceID.contains(".ru.") || 
                        sourceID == "ru"
        let isUS = usInputSources.contains(sourceID)
        
        guard isUS || isRussian else {
            return false
        }
        
        guard let bundleID = frontmostBundleID() else {
            return false
        }
        if excludedBundleIDs.contains(bundleID) {
            return false
        }
        return allowedBundleIDs.contains(bundleID) || smartBilingualAllowedBundleIDs.contains(bundleID)
    }
    
    private func eventText(_ event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else {
            return nil
        }
        
        var chars = Array<UniChar>(repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }
    
    private func isWordCharacter(_ character: Character) -> Bool {
        if triggerMap.keys.contains(character) {
            return true
        }
        return character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
    }
    
    private func isBoundary(_ text: String) -> Bool {
        guard text.count == 1, let character = text.first else {
            return false
        }
        return !isWordCharacter(character)
    }
    
    private func containsTrigger(_ token: String) -> Bool {
        token.contains { triggerMap.keys.contains($0) }
    }
    
    private func startsWithTrigger(_ token: String) -> Bool {
        token.first.map { triggerMap.keys.contains($0) } ?? false
    }
    
    private func replacementCandidate(for token: String) -> String? {
        guard containsTrigger(token) else {
            return nil
        }
        
        let chars = Array(token)
        for (index, character) in chars.enumerated() where triggerMap.keys.contains(character) {
            let atEnd = index == chars.count - 1
            let nextIsWord = !atEnd && isWordCharacter(chars[index + 1])
            if index == 0 {
                if atEnd || !nextIsWord {
                    return nil
                }
                continue
            }
            
            let previousIsWord = index > 0 && isWordCharacter(chars[index - 1])
            if !previousIsWord || (!nextIsWord && !atEnd) {
                return nil
            }
        }
        
        let replaced = String(chars.map { triggerMap[$0] ?? $0 })
        return replaced == token ? nil : replaced
    }
    
    private func containsScalar(from set: CharacterSet, in text: String) -> Bool {
        text.unicodeScalars.contains { set.contains($0) }
    }
    
    private func isSingleInitialUppercaseAaToken(_ token: String) -> Bool {
        let chars = Array(token)
        guard chars.count == 2, chars[1] == "[" else {
            return false
        }
        return chars[0].unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
    }
    
    private func isEnglishContractionSuffix(_ token: String) -> Bool {
        token == "'s" || token == "'S" || token == "‘s" || token == "‘S" || token == "’s" || token == "’S"
    }
    
    private func isPlausibleDanishToken(_ token: String) -> Bool {
        if isEnglishContractionSuffix(token) {
            return false
        }
        
        if containsScalar(from: .decimalDigits, in: token) {
            return false
        }
        
        let hasLowercase = containsScalar(from: .lowercaseLetters, in: token)
        let hasUppercase = containsScalar(from: .uppercaseLetters, in: token)
        if hasUppercase && !hasLowercase {
            return isSingleInitialUppercaseAaToken(token)
        }
        
        let chars = Array(token)
        for (index, character) in chars.enumerated() where uppercaseTriggers.contains(character) {
            if index != 0 {
                return false
            }
        }
        
        return true
    }
    
    private func isValidDanishWord(_ word: String) -> Bool {
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: danishLanguage,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
    
    private func replacementForCurrentToken() -> String? {
        replacementForToken(buffer.token)
    }
    
    private func replacementForToken(_ token: String) -> String? {
        guard isPlausibleDanishToken(token) else {
            return nil
        }
        guard let candidate = replacementCandidate(for: token) else {
            return nil
        }
        return isValidDanishWord(candidate) ? candidate : nil
    }
    
    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.setIntegerValueField(.eventSourceUserData, value: magicEventTag)
        up?.setIntegerValueField(.eventSourceUserData, value: magicEventTag)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    private func postText(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        var utf16 = Array(text.utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        down?.setIntegerValueField(.eventSourceUserData, value: magicEventTag)
        up?.setIntegerValueField(.eventSourceUserData, value: magicEventTag)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    private func replaceToken(with replacement: String, boundary: String) {
        for _ in buffer.token {
            postKey(51) // Delete / Backspace
        }
        postText(replacement + boundary)
        buffer.reset()
    }
    
    private func replacePendingToken(with replacement: String) {
        for _ in buffer.token.dropLast() {
            postKey(51) // Delete / Backspace
        }
        postText(replacement)
        buffer.reset()
    }

    private static let qwertyToYuken: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З", "{": "Х", "}": "Ъ",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
        "`": "ё", "~": "Ё",
    ]

    private static let yukenToQwerty: [Character: Character] = {
        var map = [Character: Character]()
        for (k, v) in qwertyToYuken {
            map[v] = k
        }
        return map
    }()

    private func translateEnglishToRussian(_ token: String) -> String {
        return String(token.map { Self.qwertyToYuken[$0] ?? $0 })
    }

    private func translateRussianToEnglish(_ token: String) -> String {
        return String(token.map { Self.yukenToQwerty[$0] ?? $0 })
    }

    private func findLayouts() -> (english: String?, russian: String?) {
        let client = SystemInputSourceClient()
        let sources = client.availableInputSources()
        
        let english = sources.first { source in
            let id = source.sourceID.lowercased()
            return (id.contains(".us") || id.contains(".abc") || source.languageTag == "en") &&
                   !id.contains("characterpalette") && !id.contains("ink")
        }?.sourceID ?? "com.apple.keylayout.US"
        
        let russian = sources.first { source in
            let id = source.sourceID.lowercased()
            return (id.contains("russian") || source.languageTag == "ru") &&
                   !id.contains("characterpalette") && !id.contains("ink")
        }?.sourceID ?? "com.apple.keylayout.RussianWin"
        
        return (english, russian)
    }

    private func isValidEnglishWord(_ word: String) -> Bool {
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: "en",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }

    private func isValidRussianWord(_ word: String) -> Bool {
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: "ru",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }

    private func hasGuesses(for word: String, language: String) -> Bool {
        let range = NSRange(location: 0, length: word.utf16.count)
        let guesses = checker.guesses(forWordRange: range, in: word, language: language, inSpellDocumentWithTag: 0)
        return guesses != nil && !guesses!.isEmpty
    }

    public struct BilingualResult {
        public let replacement: String
        public let targetLayoutID: String?
    }

    public func checkBilingualConversion(for token: String) -> BilingualResult? {
        guard token.count >= 3 else { return nil }
        guard !token.isEmpty else { return nil }
        guard let sourceID = currentInputSourceID() else { return nil }
        
        let isUS = usInputSources.contains(sourceID)
        let isRussian = sourceID.localizedCaseInsensitiveContains("Russian") || 
                        sourceID.hasSuffix(".ru") || 
                        sourceID.contains(".ru.") || 
                        sourceID == "ru"
        
        if isUS {
            if isValidEnglishWord(token) {
                return nil
            }
            
            let translated = translateEnglishToRussian(token)
            let isWord = isValidRussianWord(translated)
            let isLikelyWord = token.count >= 4 && hasGuesses(for: translated, language: "ru")
            
            if isWord || isLikelyWord {
                let (_, russianLayoutID) = findLayouts()
                return BilingualResult(replacement: translated, targetLayoutID: russianLayoutID)
            }
        } else if isRussian {
            if isValidRussianWord(token) {
                return nil
            }
            
            let translated = translateRussianToEnglish(token)
            let isWord = isValidEnglishWord(translated)
            let isLikelyWord = token.count >= 4 && hasGuesses(for: translated, language: "en")
            
            if isWord || isLikelyWord {
                let (englishLayoutID, _) = findLayouts()
                return BilingualResult(replacement: translated, targetLayoutID: englishLayoutID)
            }
        }
        
        return nil
    }
}
