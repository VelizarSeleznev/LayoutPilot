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
    
    private let commonRussianShortWords: Set<String> = [
        "а", "в", "и", "к", "о", "с", "у", "я",
        "бы", "во", "вы", "да", "до", "ее", "её", "же", "за", "из", "им", "их", "ли", "мы", "на", "не", "но", "он", "от", "по", "со", "та", "те", "то", "ту", "ты",
        "об", "уж", "ей", "ею", "ко"
    ]

    private let commonEnglishShortWords: Set<String> = [
        "a", "i",
        "am", "an", "as", "at", "be", "by", "do", "go", "he", "if", "in", "is", "it", "me", "my", "no", "of", "on", "or", "so", "to", "up", "us", "we",
        "ah", "oh"
    ]

    
    final class WordBuffer {
        var token = ""
        func append(_ text: String) {
            token += text
        }
        func reset() {
            token = ""
        }
        func removeLast() {
            if !token.isEmpty {
                token.removeLast()
            }
        }
    }
    
    final class ContextHistory {
        private var words: [String] = []
        private let maxCount = 5
        
        func append(_ word: String) {
            words.append(word)
            if words.count > maxCount {
                words.removeFirst()
            }
        }
        
        func reset() {
            words.removeAll()
        }
        
        func getWords() -> [String] {
            return words
        }
    }
    
    private let buffer = WordBuffer()
    let contextHistory = ContextHistory()
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

    private var _smartBilingualUndoDelay = 0.5

    public var smartBilingualUndoDelay: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _smartBilingualUndoDelay
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _smartBilingualUndoDelay = newValue
        }
    }

    private var _cachedEnglishLayoutID: String?
    private var _cachedRussianLayoutID: String?

    private var cachedEnglishLayoutID: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _cachedEnglishLayoutID
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _cachedEnglishLayoutID = newValue
        }
    }

    private var cachedRussianLayoutID: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _cachedRussianLayoutID
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _cachedRussianLayoutID = newValue
        }
    }

    private struct LastReplacementInfo {
        let mode: String
        let reason: String
        let original: String
        let replacement: String
        let boundary: String
        let timestamp: Date
        let bundleID: String?
        let originalLayoutID: String?
        let targetLayoutID: String?
        var isActive: Bool
    }

    private var lastReplacement: LastReplacementInfo?
    
    private var eventTap: CFMachPort?
    private var isStarted = false
    
    public init() {}
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        requestAccessibilityPermissionIfNeeded()
        cacheLayouts()
        
        NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cacheLayouts()
        }
        
        Thread.detachNewThread { [weak self] in
            self?.runEventLoop()
        }
    }

    private func cacheLayouts() {
        if Thread.isMainThread {
            self.performLayoutCaching()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performLayoutCaching()
            }
        }
    }

    private func performLayoutCaching() {
        let client = SystemInputSourceClient()
        let sources = client.availableInputSources()
        
        let english = sources.first { source in
            let id = source.sourceID.lowercased()
            return (id.contains(".us") || id.contains(".abc") || source.languageTag?.hasPrefix("en") == true) &&
                   !id.contains("characterpalette") && !id.contains("ink")
        }?.sourceID ?? "com.apple.keylayout.US"
        
        let russian = sources.first { source in
            let id = source.sourceID.lowercased()
            return (id.contains("russian") || source.languageTag?.hasPrefix("ru") == true) &&
                   !id.contains("characterpalette") && !id.contains("ink")
        }?.sourceID ?? "com.apple.keylayout.RussianWin"
        
        self.cachedEnglishLayoutID = english
        self.cachedRussianLayoutID = russian
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

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 51 { // Backspace / Delete
            if let last = lastReplacement, last.isActive {
                let elapsed = Date().timeIntervalSince(last.timestamp)
                if elapsed <= _smartBilingualUndoDelay {
                    performReplacementUndo(last, elapsed: elapsed, keyCode: keyCode)
                    return nil // Swallow event!
                } else {
                    lastReplacement?.isActive = false
                    SmartInputEventLog.shared.record(.init(
                        kind: "backspace_after_replacement_window",
                        mode: last.mode,
                        reason: "undo window expired",
                        bundleID: last.bundleID,
                        sourceLayoutID: last.originalLayoutID,
                        targetLayoutID: last.targetLayoutID,
                        original: last.original,
                        replacement: last.replacement,
                        boundary: last.boundary,
                        keyCode: keyCode,
                        bufferBefore: buffer.token,
                        elapsedSinceReplacement: elapsed,
                        replacementAgeLimit: _smartBilingualUndoDelay
                    ))
                }
            }
            let bufferBefore = buffer.token
            buffer.removeLast()
            if bufferBefore != buffer.token {
                SmartInputEventLog.shared.record(.init(
                    kind: "backspace_buffer_update",
                    reason: "removed last buffered character",
                    bundleID: frontmostBundleID(),
                    sourceLayoutID: currentInputSourceID(),
                    keyCode: keyCode,
                    bufferBefore: bufferBefore,
                    bufferAfter: buffer.token
                ))
            }
            return Unmanaged.passUnretained(event)
        } else if keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126 || keyCode == 53 || keyCode == 48 || keyCode == 36 {
            // Arrow keys (123-126), Escape (53), Tab (48), Return (36)
            buffer.reset()
            contextHistory.reset()
            lastReplacement?.isActive = false
        } else {
            lastReplacement?.isActive = false
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
            contextHistory.reset()
            return Unmanaged.passUnretained(event)
        }
        
        guard shouldHandleCurrentContext() else {
            buffer.reset()
            contextHistory.reset()
            return Unmanaged.passUnretained(event)
        }
        
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            buffer.reset()
            contextHistory.reset()
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
                let originalToken = buffer.token
                replaceToken(with: replacement, boundary: text)
                recordReplacementForUndo(
                    mode: "danish",
                    reason: "valid Danish boundary replacement",
                    original: originalToken,
                    replacement: replacement,
                    boundary: text,
                    bundleID: activeBundleID,
                    originalLayoutID: sourceID,
                    targetLayoutID: nil
                )
                return nil
            }
            
            if smartBilingualEnabled,
               isBilingualAllowed,
               let bilingualResult = checkBilingualConversion(for: buffer.token) {
                let originalLayoutID = currentInputSourceID()
                let originalToken = buffer.token
                
                let (_, russianLayoutID) = findLayouts()
                let isToRussian = (bilingualResult.targetLayoutID == russianLayoutID)
                let convertedBoundary: String
                if isToRussian {
                    convertedBoundary = translateEnglishToRussian(text)
                } else {
                    convertedBoundary = translateRussianToEnglish(text)
                }
                
                replaceToken(with: bilingualResult.replacement, boundary: convertedBoundary)
                
                recordReplacementForUndo(
                    mode: "bilingual",
                    reason: "converted token is more likely in opposing layout",
                    original: originalToken,
                    replacement: bilingualResult.replacement,
                    boundary: convertedBoundary,
                    bundleID: activeBundleID,
                    originalLayoutID: originalLayoutID,
                    targetLayoutID: bilingualResult.targetLayoutID
                )
                
                contextHistory.append(bilingualResult.replacement)
                
                if let targetLayoutID = bilingualResult.targetLayoutID {
                    if shouldSwitchLayout(to: targetLayoutID, replacement: bilingualResult.replacement) {
                        DispatchQueue.main.async {
                            try? SystemInputSourceClient().activateInputSource(withID: targetLayoutID)
                        }
                    }
                }
                return nil
            }
            
            if !buffer.token.isEmpty {
                contextHistory.append(buffer.token)
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
                let originalToken = buffer.token
                replacePendingToken(with: replacement)
                recordReplacementForUndo(
                    mode: "danish",
                    reason: "valid Danish pending replacement",
                    original: originalToken,
                    replacement: replacement,
                    boundary: "",
                    bundleID: activeBundleID,
                    originalLayoutID: sourceID,
                    targetLayoutID: nil
                )
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
        usleep(3000)
        up?.post(tap: .cghidEventTap)
        usleep(3000)
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
        usleep(3000)
        up?.post(tap: .cghidEventTap)
        usleep(3000)
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
        let english = cachedEnglishLayoutID ?? "com.apple.keylayout.US"
        let russian = cachedRussianLayoutID ?? "com.apple.keylayout.RussianWin"
        return (english, russian)
    }

    private func isValidEnglishWord(_ word: String) -> Bool {
        if word.count == 1 {
            return commonEnglishShortWords.contains(word.lowercased())
        }
        if word.lowercased() == "i" {
            return true
        }
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
        if word.count == 1 {
            return commonRussianShortWords.contains(word.lowercased())
        }
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

    private func isLatinWord(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }

    private func isCyrillicWord(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { scalar in
            (0x0400...0x04FF).contains(scalar.value)
        }
    }

    public struct BilingualResult {
        public let replacement: String
        public let targetLayoutID: String?
    }

    public func checkBilingualConversion(for token: String) -> BilingualResult? {
        guard !token.isEmpty else { return nil }
        guard let sourceID = currentInputSourceID() else { return nil }
        
        let isUS = usInputSources.contains(sourceID)
        let isRussian = sourceID.localizedCaseInsensitiveContains("Russian") || 
                        sourceID.hasSuffix(".ru") || 
                        sourceID.contains(".ru.") || 
                        sourceID == "ru"
        
        if token.count == 1 {
            return nil
        }

        if token.count < 3 {
            if isUS {
                guard isLatinWord(token) else { return nil }
                if isValidEnglishWord(token) {
                    return nil
                }
                let translated = translateEnglishToRussian(token)
                if translated == token {
                    return nil
                }
                guard isCyrillicWord(translated) else { return nil }
                if commonRussianShortWords.contains(translated.lowercased()) && isValidRussianWord(translated) {
                    let (_, russianLayoutID) = findLayouts()
                    return BilingualResult(replacement: translated, targetLayoutID: russianLayoutID)
                }
            } else if isRussian {
                guard isCyrillicWord(token) else { return nil }
                if isValidRussianWord(token) {
                    return nil
                }
                let translated = translateRussianToEnglish(token)
                if translated == token {
                    return nil
                }
                guard isLatinWord(translated) else { return nil }
                if commonEnglishShortWords.contains(translated.lowercased()) && isValidEnglishWord(translated) {
                    let (englishLayoutID, _) = findLayouts()
                    return BilingualResult(replacement: translated, targetLayoutID: englishLayoutID)
                }
            }
            return nil
        }
        
        if isUS {
            guard isLatinWord(token) else { return nil }
            if isValidEnglishWord(token) {
                return nil
            }
            
            let translated = translateEnglishToRussian(token)
            guard isCyrillicWord(translated) else { return nil }
            let isWord = isValidRussianWord(translated)
            let isLikelyWord = token.count >= 4 &&
                               hasGuesses(for: translated, language: "ru") &&
                               !hasGuesses(for: token, language: "en")
            
            if isWord || isLikelyWord {
                let (_, russianLayoutID) = findLayouts()
                return BilingualResult(replacement: translated, targetLayoutID: russianLayoutID)
            }
        } else if isRussian {
            guard isCyrillicWord(token) else { return nil }
            if isValidRussianWord(token) {
                return nil
            }
            
            let translated = translateRussianToEnglish(token)
            guard isLatinWord(translated) else { return nil }
            let isWord = isValidEnglishWord(translated)
            let isLikelyWord = token.count >= 4 &&
                               hasGuesses(for: translated, language: "en") &&
                               !hasGuesses(for: token, language: "ru")
            
            if isWord || isLikelyWord {
                let (englishLayoutID, _) = findLayouts()
                return BilingualResult(replacement: translated, targetLayoutID: englishLayoutID)
            }
        }
        
        return nil
    }

    private func recordReplacementForUndo(
        mode: String,
        reason: String,
        original: String,
        replacement: String,
        boundary: String,
        bundleID: String?,
        originalLayoutID: String?,
        targetLayoutID: String?
    ) {
        lastReplacement = LastReplacementInfo(
            mode: mode,
            reason: reason,
            original: original,
            replacement: replacement,
            boundary: boundary,
            timestamp: Date(),
            bundleID: bundleID,
            originalLayoutID: originalLayoutID,
            targetLayoutID: targetLayoutID,
            isActive: true
        )

        SmartInputEventLog.shared.record(.init(
            kind: "replacement",
            mode: mode,
            reason: reason,
            bundleID: bundleID,
            sourceLayoutID: originalLayoutID,
            targetLayoutID: targetLayoutID,
            original: original,
            replacement: replacement,
            boundary: boundary,
            replacementAgeLimit: _smartBilingualUndoDelay
        ))
    }

    private func performReplacementUndo(_ last: LastReplacementInfo, elapsed: Double, keyCode: Int64) {
        lastReplacement?.isActive = false
        
        let charsToDeleteCount = last.replacement.count + last.boundary.count
        for _ in 0..<charsToDeleteCount {
            postKey(51) // Post Backspace
        }
        
        postText(last.original)
        
        if let originalLayoutID = last.originalLayoutID {
            DispatchQueue.main.async {
                try? SystemInputSourceClient().activateInputSource(withID: originalLayoutID)
            }
        }
        
        buffer.reset()

        SmartInputEventLog.shared.record(.init(
            kind: "replacement_undo",
            mode: last.mode,
            reason: "backspace within undo window",
            bundleID: last.bundleID,
            sourceLayoutID: last.originalLayoutID,
            targetLayoutID: last.targetLayoutID,
            original: last.original,
            replacement: last.replacement,
            boundary: last.boundary,
            keyCode: keyCode,
            bufferAfter: buffer.token,
            elapsedSinceReplacement: elapsed,
            replacementAgeLimit: _smartBilingualUndoDelay
        ))
    }

    enum WordLanguage {
        case english
        case russian
        case unknown
    }

    func detectLanguage(of word: String) -> WordLanguage {
        let hasCyrillic = word.unicodeScalars.contains { scalar in
            (0x0400...0x04FF).contains(scalar.value)
        }
        let hasLatin = word.unicodeScalars.contains { scalar in
            let val = scalar.value
            return (97...122).contains(val) || (65...90).contains(val)
        }
        if hasCyrillic && !hasLatin { return .russian }
        if hasLatin && !hasCyrillic { return .english }
        return .unknown
    }

    func shouldSwitchLayout(to targetLayoutID: String, replacement: String) -> Bool {
        let targetLang = detectLanguage(of: replacement)
        guard targetLang != .unknown else { return true }
        
        let opposingLang: WordLanguage = (targetLang == .english) ? .russian : .english
        let history = contextHistory.getWords()
        
        // Count opposing words in history
        let opposingCount = history.filter { detectLanguage(of: $0) == opposingLang }.count
        if opposingCount == 0 {
            return true
        }
        
        // Check if last word in history is also of target language (making it 2 consecutive target words)
        if let lastWord = history.last, detectLanguage(of: lastWord) == targetLang {
            return true
        }
        
        return false
    }
}
