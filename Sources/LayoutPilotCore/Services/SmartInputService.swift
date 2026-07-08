import AppKit
import Carbon
import CoreGraphics
import Foundation
import OSLog

public final class SmartInputService: @unchecked Sendable {
    public static let shared = SmartInputService()

    /// Invoked (on the tap thread) when the global Rewrite hotkey fires.
    /// Set once at launch; the handler hops to the main actor itself.
    public var onRewriteHotkey: (@Sendable () -> Void)?

    private let magicEventTag: Int64 = 0x44414E495348 // "DANISH"
    private let logger = Logger(
        subsystem: "com.velizard.LayoutPilot",
        category: "SmartInputService"
    )
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
        private let maxCount = 8
        
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
    let learningStore: SmartInputLearningStore
    
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

    // MARK: - Spelling Autocorrect properties
    public var onShowSuggestions: (@Sendable (SpellingSuggestionContext) -> Void)?
    public var onHideSuggestions: (@Sendable () -> Void)?

    private var _spellingAutocorrectEnabled = true
    public var spellingAutocorrectEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _spellingAutocorrectEnabled
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _spellingAutocorrectEnabled = newValue
        }
    }

    private var _suggestionsActive = false
    public var isSuggestionsActive: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _suggestionsActive
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _suggestionsActive = newValue
        }
    }

    private var _activeSuggestions: [String] = []
    private var activeSuggestions: [String] {
        get {
            lock.lock(); defer { lock.unlock() }
            return _activeSuggestions
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _activeSuggestions = newValue
        }
    }

    private var _activeSelectCallback: (@Sendable (String) -> Void)?
    private var activeSelectCallback: (@Sendable (String) -> Void)? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _activeSelectCallback
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _activeSelectCallback = newValue
        }
    }

    // MARK: - Thread-safe wrappers
    private func getBufferToken() -> String {
        lock.lock(); defer { lock.unlock() }
        return buffer.token
    }
    
    private func appendToBuffer(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(text)
    }
    
    private func resetBuffer() {
        lock.lock(); defer { lock.unlock() }
        buffer.reset()
    }
    
    private func removeLastFromBuffer() {
        lock.lock(); defer { lock.unlock() }
        buffer.removeLast()
    }

    private func appendToContextHistory(_ word: String) {
        lock.lock(); defer { lock.unlock() }
        contextHistory.append(word)
    }

    private func resetContextHistory() {
        lock.lock(); defer { lock.unlock() }
        contextHistory.reset()
    }

    private func getContextHistoryWords() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return contextHistory.getWords()
    }

    private func getLastReplacement() -> LastReplacementInfo? {
        lock.lock(); defer { lock.unlock() }
        return _lastReplacement
    }

    private func setLastReplacement(_ info: LastReplacementInfo?) {
        lock.lock(); defer { lock.unlock() }
        _lastReplacement = info
    }

    private func deactivateLastReplacement() {
        lock.lock(); defer { lock.unlock() }
        _lastReplacement?.isActive = false
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


    private var _smartBilingualApplyToAll = false
    private var _danishApplyToAll = false

    /// When true, smart RU/EN autocorrection runs in every app except `excludedBundleIDs`.
    public var smartBilingualApplyToAll: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _smartBilingualApplyToAll
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _smartBilingualApplyToAll = newValue
        }
    }

    /// When true, smart Danish input runs in every app except `excludedBundleIDs`.
    public var danishApplyToAll: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _danishApplyToAll
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _danishApplyToAll = newValue
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

    private var _textSnippetsEnabled = true
    private var _textSnippets: [TextSnippet] = []

    public var textSnippetsEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _textSnippetsEnabled
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _textSnippetsEnabled = newValue
        }
    }

    public var textSnippets: [TextSnippet] {
        get {
            lock.lock(); defer { lock.unlock() }
            return _textSnippets
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _textSnippets = newValue
        }
    }

    private var _smartBilingualUndoDelay = 3.0

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
        var timestamp: Date
        let bundleID: String?
        let originalLayoutID: String?
        let targetLayoutID: String?
        var isActive: Bool
        var boundaryBackspaceConsumed: Bool
    }

    private var _lastReplacement: LastReplacementInfo?
    
    private var eventTap: CFMachPort?
    private var isStarted = false
    
    public init() {
        self.learningStore = .shared
    }

    init(learningStore: SmartInputLearningStore) {
        self.learningStore = learningStore
    }
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        
        requestAccessibilityPermissionIfNeeded()
        cacheLayouts()
        learningStore.bootstrapFromEventLogIfNeeded()
        
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
        guard let runLoop = CFRunLoopGetCurrent() else {
            logger.error("Failed to get smart input event tap run loop")
            return
        }
        
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
                logger.error("Failed to create smart input event tap")
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            
            self.eventTap = tap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
            let watchdogTimer = CFRunLoopTimerCreateWithHandler(
                kCFAllocatorDefault,
                CFAbsoluteTimeGetCurrent() + 1.0,
                1.0,
                0,
                0
            ) { [weak self] _ in
                self?.recoverEventTapIfNeeded(tap: tap, runLoop: runLoop)
            }
            CFRunLoopAddTimer(runLoop, watchdogTimer, .commonModes)

            CGEvent.tapEnable(tap: tap, enable: true)
            logger.info("Smart input event tap started")
            
            CFRunLoopRun()

            CFRunLoopTimerInvalidate(watchdogTimer)
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
            if self.eventTap === tap {
                self.eventTap = nil
            }
        }
    }
    
    private func requestAccessibilityPermissionIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoverEventTapAfterDisable(reason: type == .tapDisabledByTimeout ? "timeout" : "user_input")
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        if event.getIntegerValueField(.eventSourceUserData) == magicEventTag {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if shouldForceUSForSpotlight(keyCode: keyCode, flags: flags) {
            activatePreferredUSInputSource()
            resetBuffer()
            resetContextHistory()
            deactivateLastReplacement()
            if isSuggestionsActive {
                isSuggestionsActive = false
                onHideSuggestions?()
            }
            return Unmanaged.passUnretained(event)
        }

        let activeBundleID = frontmostBundleID() ?? ""
        if shouldForceUSForBrowserNewTab(keyCode: keyCode, flags: flags, bundleID: activeBundleID) {
            activatePreferredUSInputSource()
            resetBuffer()
            resetContextHistory()
            deactivateLastReplacement()
            if isSuggestionsActive {
                isSuggestionsActive = false
                onHideSuggestions?()
            }
            return Unmanaged.passUnretained(event)
        }

        // Global Rewrite hotkey: Option+Shift+R (swallowed, handled in app layer).
        if keyCode == 15 {
            if flags.contains(.maskAlternate), flags.contains(.maskShift),
               !flags.contains(.maskCommand), !flags.contains(.maskControl),
               let handler = onRewriteHotkey {
                handler()
                return nil
            }
        }

        // Intercept suggestions keys when panel is active
        if isSuggestionsActive {
            if keyCode == 53 { // Escape
                isSuggestionsActive = false
                onHideSuggestions?()
                return nil // Swallow Escape to close the panel
            }
            
            if flags.contains(.maskAlternate) {
                var selectedIndex: Int? = nil
                if keyCode == 18 { selectedIndex = 0 }      // ⌥1
                else if keyCode == 19 { selectedIndex = 1 } // ⌥2
                else if keyCode == 20 { selectedIndex = 2 } // ⌥3
                else if keyCode == 21 { selectedIndex = 3 } // ⌥4
                else if keyCode == 23 { selectedIndex = 4 } // ⌥5
                
                if let idx = selectedIndex {
                    let suggs = activeSuggestions
                    let callback = activeSelectCallback
                    if idx < suggs.count {
                        let selected = suggs[idx]
                        isSuggestionsActive = false
                        onHideSuggestions?()
                        callback?(selected)
                        return nil // Swallow hotkey
                    }
                }
            }
            
            // Hide on any other key except Backspace (handled below)
            if keyCode != 51 {
                isSuggestionsActive = false
                onHideSuggestions?()
            }
        }

        if keyCode == 51 { // Backspace / Delete
            if isSuggestionsActive {
                isSuggestionsActive = false
                onHideSuggestions?()
            }
            if let last = getLastReplacement(), last.isActive {
                let elapsed = Date().timeIntervalSince(last.timestamp)
                if elapsed <= _smartBilingualUndoDelay {
                    if !last.boundary.isEmpty, !last.boundaryBackspaceConsumed {
                        markReplacementBoundaryBackspaceConsumed(last, elapsed: elapsed, keyCode: keyCode)
                        return Unmanaged.passUnretained(event)
                    }
                    performReplacementUndo(
                        last,
                        elapsed: elapsed,
                        keyCode: keyCode,
                        deleteBoundary: !last.boundaryBackspaceConsumed
                    )
                    return nil // Swallow event.
                } else {
                    deactivateLastReplacement()
                    if last.boundary.isEmpty || last.boundaryBackspaceConsumed {
                        recordRejectedConversionIfNeeded(last)
                        SmartInputEventLog.shared.record(.init(
                            kind: "backspace_after_replacement_window",
                            mode: last.mode,
                            reason: "next input was backspace after undo window; learned rejected conversion",
                            bundleID: last.bundleID,
                            sourceLayoutID: last.originalLayoutID,
                            targetLayoutID: last.targetLayoutID,
                            original: last.original,
                            replacement: last.replacement,
                            boundary: last.boundary,
                            keyCode: keyCode,
                            bufferBefore: getBufferToken(),
                            elapsedSinceReplacement: elapsed,
                            replacementAgeLimit: _smartBilingualUndoDelay,
                            suppressionReason: "learned_user_rejection"
                        ))
                    }
                }
            }
            let bufferBefore = getBufferToken()
            removeLastFromBuffer()
            let bufferAfter = getBufferToken()
            if bufferBefore != bufferAfter {
                SmartInputEventLog.shared.record(.init(
                    kind: "backspace_buffer_update",
                    reason: "removed last buffered character",
                    bundleID: frontmostBundleID(),
                    sourceLayoutID: currentInputSourceID(),
                    keyCode: keyCode,
                    bufferBefore: bufferBefore,
                    bufferAfter: bufferAfter
                ))
            }
            return Unmanaged.passUnretained(event)
        } else if keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126 || keyCode == 53 || keyCode == 48 || keyCode == 36 {
            // Arrow keys (123-126), Escape (53), Tab (48), Return (36)
            resetBuffer()
            resetContextHistory()
            deactivateLastReplacement()
        } else {
            deactivateLastReplacement()
        }

        guard isEnabled || smartBilingualEnabled || textSnippetsEnabled else {
            resetBuffer()
            resetContextHistory()
            return Unmanaged.passUnretained(event)
        }
        
        guard shouldHandleCurrentContext() else {
            resetBuffer()
            resetContextHistory()
            return Unmanaged.passUnretained(event)
        }
        
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            resetBuffer()
            resetContextHistory()
            return Unmanaged.passUnretained(event)
        }
        
        guard let text = eventText(event), text.count == 1 else {
            return Unmanaged.passUnretained(event)
        }

        let snippetsAllowed = isTextSnippetsAllowed(for: activeBundleID)
        let bufferToken = getBufferToken()

        if snippetsAllowed, isSnippetTriggerContinuation(bufferToken + text) {
            appendToBuffer(text)
            return Unmanaged.passUnretained(event)
        }
        
        if isBoundary(text) {
            let isDanishAllowed = isDanishAllowed(for: activeBundleID)
            let isBilingualAllowed = isBilingualAllowed(for: activeBundleID)
            let sourceID = currentInputSourceID()

            // 1. Text snippets expansion (no spelling check on snippets)
            if snippetsAllowed,
               let snippet = textSnippet(for: bufferToken) {
                let originalToken = bufferToken
                replaceToken(with: snippet.replacement, boundary: text)
                recordReplacementForUndo(
                    mode: "snippet",
                    reason: "expanded text snippet trigger",
                    original: originalToken,
                    replacement: snippet.replacement,
                    boundary: text,
                    bundleID: activeBundleID,
                    originalLayoutID: sourceID,
                    targetLayoutID: nil,
                    contextBefore: getContextHistoryWords()
                )
                return nil
            }

            // Perform logical conversion / healing
            var healedWord: String? = nil
            var conversionMode: String? = nil
            var conversionReason: String? = nil
            var targetLayoutID: String? = nil
            var detectedLanguage: String? = nil
            
            // Check Danish replacement
            if isDanishAllowed,
               let sourceID,
               usInputSources.contains(sourceID),
               let replacement = replacementForToken(bufferToken) {
                healedWord = replacement
                conversionMode = "danish"
                conversionReason = "valid Danish boundary replacement"
                detectedLanguage = "da"
            }
            // Check Capitalization Correction
            else if smartBilingualEnabled,
                    isBilingualAllowed,
                    let sourceID,
                    let correctedToken = capitalizationCorrection(for: bufferToken, sourceLayoutID: sourceID) {
                healedWord = correctedToken
                conversionMode = "capitalization"
                conversionReason = "corrected accidental double initial uppercase"
                detectedLanguage = detectLanguage(of: correctedToken) == .russian ? "ru" : "en"
            }
            // Check Bilingual Layout Conversion
            else if smartBilingualEnabled,
                    isBilingualAllowed,
                    let sourceID,
                    let bilingualResult = checkBilingualConversion(
                        for: bufferToken,
                        bundleID: activeBundleID,
                        logSuppression: true
                    ) {
                healedWord = bilingualResult.replacement
                conversionMode = "bilingual"
                conversionReason = "converted token is more likely in opposing layout"
                targetLayoutID = bilingualResult.targetLayoutID
                
                let (_, russianLayoutID) = findLayouts()
                detectedLanguage = (bilingualResult.targetLayoutID == russianLayoutID) ? "ru" : "en"
            }
            
            let wordToCheck = healedWord ?? bufferToken
            let originalToken = bufferToken
            
            // Determine language for spell check
            if detectedLanguage == nil {
                let lang = detectLanguage(of: wordToCheck)
                if lang == .russian {
                    detectedLanguage = "ru"
                } else if lang == .english {
                    detectedLanguage = "en"
                } else if let sourceID {
                    detectedLanguage = sourceID.localizedCaseInsensitiveContains("Russian") ||
                                       sourceID.hasSuffix(".ru") ||
                                       sourceID.contains(".ru.") ||
                                       sourceID == "ru" ? "ru" : "en"
                } else {
                    detectedLanguage = "en"
                }
            }
            
            // Run spelling autocorrection check
            var finalWord = wordToCheck
            var spellingApplied = false
            var spellingSuggestions: [String] = []
            
            if spellingAutocorrectEnabled,
               !wordToCheck.isEmpty,
               let lang = detectedLanguage,
               isMisspelled(wordToCheck, language: lang, layoutID: sourceID) {
                
                let guesses = suggestionsForWord(wordToCheck, language: lang)
                if !guesses.isEmpty {
                    spellingSuggestions = guesses
                    finalWord = guesses[0]
                    spellingApplied = true
                }
            }
            
            // Perform actual replacement
            if conversionMode != nil || spellingApplied {
                let contextBefore = getContextHistoryWords()
                
                var convertedBoundary = text
                if conversionMode == "bilingual", let targetLayoutID {
                    let (_, russianLayoutID) = findLayouts()
                    if targetLayoutID == russianLayoutID {
                        convertedBoundary = translateEnglishToRussian(text)
                    } else {
                        convertedBoundary = translateRussianToEnglish(text)
                    }
                }
                
                replaceToken(with: finalWord, boundary: convertedBoundary)
                
                let mode = spellingApplied ? "spelling" : (conversionMode ?? "unknown")
                let reason = spellingApplied 
                    ? "spelling auto-corrected '\(wordToCheck)' to '\(finalWord)' after \(conversionMode ?? "no") conversion"
                    : (conversionReason ?? "")
                
                recordReplacementForUndo(
                    mode: mode,
                    reason: reason,
                    original: originalToken,
                    replacement: finalWord,
                    boundary: convertedBoundary,
                    bundleID: activeBundleID,
                    originalLayoutID: sourceID,
                    targetLayoutID: targetLayoutID,
                    contextBefore: contextBefore
                )
                
                appendToContextHistory(finalWord)
                
                if let targetLayoutID {
                    if shouldSwitchLayout(to: targetLayoutID, replacement: finalWord) {
                        DispatchQueue.main.async {
                            try? SystemInputSourceClient().activateInputSource(withID: targetLayoutID)
                        }
                    }
                }
                
                if spellingApplied {
                    let finalConvertedBoundary = convertedBoundary
                    let originalLanguage = detectedLanguage ?? "en"
                    
                    // Show Suggestions UI
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        
                        // We also provide the original word as a choice to revert!
                        // Put original word at the very end of active suggestions
                        var suggList = spellingSuggestions
                        if !suggList.contains(originalToken) {
                            suggList.append(originalToken)
                        }
                        
                        self.activeSuggestions = suggList
                        self.activeSelectCallback = { [weak self] selectedWord in
                            guard let self else { return }
                            self.replaceAutoCorrectedWord(
                                original: originalToken,
                                autocorrected: finalWord,
                                replacement: selectedWord,
                                boundary: finalConvertedBoundary
                            )
                            if selectedWord == originalToken {
                                self.learningStore.recordRejectedConversion(
                                    mode: "spelling",
                                    original: originalToken,
                                    replacement: finalWord,
                                    sourceLayoutID: sourceID,
                                    targetLayoutID: nil,
                                    bundleID: activeBundleID
                                )
                            } else {
                                self.recordAcceptedTypedWord(selectedWord, layoutID: sourceID, bundleID: activeBundleID)
                            }
                        }
                        
                        let context = SpellingSuggestionContext(
                            originalWord: originalToken,
                            suggestions: suggList,
                            selectCallback: self.activeSelectCallback!
                        )
                        self.isSuggestionsActive = true
                        self.onShowSuggestions?(context)
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.isSuggestionsActive = false
                        self?.onHideSuggestions?()
                    }
                }
                
                return nil
            }
            
            if !bufferToken.isEmpty {
                recordAcceptedTypedWord(
                    bufferToken,
                    layoutID: sourceID,
                    bundleID: activeBundleID
                )
            }
            resetBuffer()
            DispatchQueue.main.async { [weak self] in
                self?.isSuggestionsActive = false
                self?.onHideSuggestions?()
            }
            return Unmanaged.passUnretained(event)
        }
        
        if let character = text.first, isWordCharacter(character) {
            appendToBuffer(text)
            
            let isDanishAllowed = isDanishAllowed(for: activeBundleID)
            let updatedBufferToken = getBufferToken()

            if isDanishAllowed,
               let sourceID = currentInputSourceID(),
               usInputSources.contains(sourceID),
               (triggerMap.keys.contains(character) || startsWithTrigger(updatedBufferToken)),
               let replacement = replacementForToken(updatedBufferToken) {
                let originalToken = updatedBufferToken
                replacePendingToken(with: replacement)
                recordReplacementForUndo(
                    mode: "danish",
                    reason: "valid Danish pending replacement",
                    original: originalToken,
                    replacement: replacement,
                    boundary: "",
                    bundleID: activeBundleID,
                    originalLayoutID: sourceID,
                    targetLayoutID: nil,
                    contextBefore: getContextHistoryWords()
                )
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        
        resetBuffer()
        return Unmanaged.passUnretained(event)
    }

    private func recoverEventTapAfterDisable(reason: String) {
        guard let eventTap else { return }
        logger.warning("Smart input event tap disabled by \(reason, privacy: .public); re-enabling")
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func recoverEventTapIfNeeded(tap: CFMachPort, runLoop: CFRunLoop) {
        guard isStarted else {
            CFRunLoopStop(runLoop)
            return
        }

        guard CFMachPortIsValid(tap) else {
            logger.error("Smart input event tap became invalid; recreating")
            CFRunLoopStop(runLoop)
            return
        }

        if !CGEvent.tapIsEnabled(tap: tap) {
            logger.warning("Smart input event tap was disabled without callback; re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    static func shouldForceUSForSpotlight(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == 49 &&
            flags.contains(.maskCommand) &&
            !flags.contains(.maskAlternate) &&
            !flags.contains(.maskControl)
    }

    private func shouldForceUSForSpotlight(keyCode: Int64, flags: CGEventFlags) -> Bool {
        Self.shouldForceUSForSpotlight(keyCode: keyCode, flags: flags)
    }

    static func shouldForceUSForBrowserNewTab(keyCode: Int64, flags: CGEventFlags, bundleID: String) -> Bool {
        keyCode == 17 &&
            flags.contains(.maskCommand) &&
            !flags.contains(.maskAlternate) &&
            !flags.contains(.maskControl) &&
            BrowserURLService.isBrowser(bundleID: bundleID)
    }

    private func shouldForceUSForBrowserNewTab(keyCode: Int64, flags: CGEventFlags, bundleID: String) -> Bool {
        Self.shouldForceUSForBrowserNewTab(keyCode: keyCode, flags: flags, bundleID: bundleID)
    }

    private func activatePreferredUSInputSource() {
        DispatchQueue.main.async { [usInputSources] in
            let client = SystemInputSourceClient()
            guard let currentSourceID = client.currentInputSourceID(),
                  !usInputSources.contains(currentSourceID) else {
                return
            }

            if (try? client.activateInputSource(withID: "com.apple.keylayout.US")) != nil {
                return
            }
            try? client.activateInputSource(withID: "com.apple.keylayout.ABC")
        }
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
        guard let bundleID = frontmostBundleID() else {
            return false
        }
        if excludedBundleIDs.contains(bundleID) {
            return false
        }

        if isTextSnippetsAllowed(for: bundleID) {
            return true
        }

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

        return isDanishAllowed(for: bundleID) || isBilingualAllowed(for: bundleID)
    }

    /// Smart Danish input applies when globally allowed for all apps, or this app is allow-listed.
    private func isDanishAllowed(for bundleID: String) -> Bool {
        if excludedBundleIDs.contains(bundleID) { return false }
        return danishApplyToAll || allowedBundleIDs.contains(bundleID)
    }

    /// Smart RU/EN autocorrection applies when globally allowed for all apps, or this app is allow-listed.
    private func isBilingualAllowed(for bundleID: String) -> Bool {
        if excludedBundleIDs.contains(bundleID) { return false }
        return smartBilingualApplyToAll || smartBilingualAllowedBundleIDs.contains(bundleID)
    }

    private func isTextSnippetsAllowed(for bundleID: String) -> Bool {
        if excludedBundleIDs.contains(bundleID) { return false }
        return textSnippetsEnabled && textSnippets.contains { $0.isEnabled }
    }

    func textSnippet(for token: String) -> TextSnippet? {
        textSnippets.first { snippet in
            snippet.isEnabled && snippet.trigger == token && !snippet.replacement.isEmpty
        }
    }

    func isSnippetTriggerContinuation(_ token: String) -> Bool {
        guard !token.isEmpty else {
            return false
        }
        return textSnippets.contains { snippet in
            snippet.isEnabled && snippet.trigger.hasPrefix(token) && snippet.trigger != token
        }
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

    private func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
    }

    private func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.lowercaseLetters.contains($0) }
    }

    private func correctingDoubleInitialUppercase(in token: String) -> String? {
        let chars = Array(token)
        guard chars.count >= 3,
              isUppercaseLetter(chars[0]),
              isUppercaseLetter(chars[1]),
              isLowercaseLetter(chars[2]) else {
            return nil
        }

        var corrected = String(chars[0])
        corrected += String(chars[1]).lowercased()
        corrected += String(chars.dropFirst(2))
        return corrected == token ? nil : corrected
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

    func capitalizationCorrection(for token: String, sourceLayoutID: String) -> String? {
        guard let corrected = correctingDoubleInitialUppercase(in: token) else {
            return nil
        }

        let isUS = usInputSources.contains(sourceLayoutID)
        let isRussian = sourceLayoutID.localizedCaseInsensitiveContains("Russian") ||
                        sourceLayoutID.hasSuffix(".ru") ||
                        sourceLayoutID.contains(".ru.") ||
                        sourceLayoutID == "ru"

        if isUS {
            guard isLatinWord(token), isValidEnglishWord(corrected) else { return nil }
            return corrected
        }

        if isRussian {
            guard isCyrillicWord(token), isValidRussianWord(corrected) else { return nil }
            return corrected
        }

        return nil
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

    func isValidEnglishWord(_ word: String) -> Bool {
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

    func isValidRussianWord(_ word: String) -> Bool {
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
        return checkBilingualConversion(
            for: token,
            sourceLayoutID: sourceID,
            contextWords: contextHistory.getWords(),
            bundleID: nil,
            logSuppression: false
        )
    }

    func checkBilingualConversion(
        for token: String,
        sourceLayoutID: String,
        contextWords: [String] = [],
        bundleID: String? = nil,
        logSuppression: Bool = false
    ) -> BilingualResult? {
        guard let candidate = bilingualCandidate(
            for: token,
            sourceLayoutID: sourceLayoutID,
            contextWords: contextWords
        ) else {
            return nil
        }

        if let suppressionReason = learningStore.suppressionReason(
            mode: "bilingual",
            original: token,
            replacement: candidate.replacement,
            sourceLayoutID: sourceLayoutID,
            targetLayoutID: candidate.targetLayoutID
        ) {
            var shouldBypass = false
            if suppressionReason == "accepted_word_dictionary" {
                let isUS = usInputSources.contains(sourceLayoutID)
                let isRussian = sourceLayoutID.localizedCaseInsensitiveContains("Russian") ||
                                sourceLayoutID.hasSuffix(".ru") ||
                                sourceLayoutID.contains(".ru.") ||
                                sourceLayoutID == "ru"
                
                if isUS {
                    shouldBypass = !isValidEnglishWord(token) && isValidRussianWord(candidate.replacement)
                } else if isRussian {
                    shouldBypass = !isValidRussianWord(token) && isValidEnglishWord(candidate.replacement)
                }
            }
            
            if !shouldBypass {
                if logSuppression {
                    SmartInputEventLog.shared.record(.init(
                        kind: "conversion_suppressed",
                        mode: "bilingual",
                        reason: "learned conversion should not be applied",
                        bundleID: bundleID,
                        sourceLayoutID: sourceLayoutID,
                        targetLayoutID: candidate.targetLayoutID,
                        original: token,
                        replacement: candidate.replacement,
                        contextBefore: contextWords,
                        suppressionReason: suppressionReason
                    ))
                }
                return nil
            }
        }

        return candidate
    }

    private func checkBilingualConversion(
        for token: String,
        bundleID: String?,
        logSuppression: Bool
    ) -> BilingualResult? {
        guard !token.isEmpty else { return nil }
        guard let sourceID = currentInputSourceID() else { return nil }
        return checkBilingualConversion(
            for: token,
            sourceLayoutID: sourceID,
            contextWords: contextHistory.getWords(),
            bundleID: bundleID,
            logSuppression: logSuppression
        )
    }

    private func bilingualCandidate(
        for token: String,
        sourceLayoutID: String,
        contextWords: [String]
    ) -> BilingualResult? {
        let isUS = usInputSources.contains(sourceLayoutID)
        let isRussian = sourceLayoutID.localizedCaseInsensitiveContains("Russian") ||
                        sourceLayoutID.hasSuffix(".ru") ||
                        sourceLayoutID.contains(".ru.") ||
                        sourceLayoutID == "ru"
        
        if token.count == 1 {
            return contextualSingleCharacterConversion(
                for: token,
                isUS: isUS,
                isRussian: isRussian,
                contextWords: contextWords
            )
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
            
            let rawTranslated = translateEnglishToRussian(token)
            let translated = correctingDoubleInitialUppercase(in: rawTranslated) ?? rawTranslated
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
            
            let rawTranslated = translateRussianToEnglish(token)
            let translated = correctingDoubleInitialUppercase(in: rawTranslated) ?? rawTranslated
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

    private func contextualSingleCharacterConversion(
        for token: String,
        isUS: Bool,
        isRussian: Bool,
        contextWords: [String]
    ) -> BilingualResult? {
        if isUS {
            guard isLatinWord(token), !isValidEnglishWord(token) else { return nil }
            let translated = translateEnglishToRussian(token)
            guard translated != token,
                  isCyrillicWord(translated),
                  commonRussianShortWords.contains(translated.lowercased()),
                  contextStronglySuggests(.russian, in: contextWords) else {
                return nil
            }
            let (_, russianLayoutID) = findLayouts()
            return BilingualResult(replacement: translated, targetLayoutID: russianLayoutID)
        }

        if isRussian {
            guard isCyrillicWord(token), !isValidRussianWord(token) else { return nil }
            let translated = translateRussianToEnglish(token)
            guard translated != token,
                  isLatinWord(translated),
                  commonEnglishShortWords.contains(translated.lowercased()),
                  contextStronglySuggests(.english, in: contextWords) else {
                return nil
            }
            let (englishLayoutID, _) = findLayouts()
            return BilingualResult(replacement: translated, targetLayoutID: englishLayoutID)
        }

        return nil
    }

    private func contextStronglySuggests(_ language: WordLanguage, in words: [String]) -> Bool {
        var targetCount = 0
        var opposingCount = 0

        for word in words.suffix(8) {
            let detected = detectLanguage(of: word)
            if detected == language {
                targetCount += 1
            } else if detected != .unknown {
                opposingCount += 1
            }
        }

        return targetCount >= 2 && targetCount >= opposingCount + 1
    }

    private func recordAcceptedTypedWord(_ word: String, layoutID: String?, bundleID: String?) {
        contextHistory.append(word)

        let outcome = learningStore.recordAcceptedWord(
            word,
            layoutID: layoutID,
            bundleID: bundleID
        )
        if outcome.wasPromoted {
            SmartInputEventLog.shared.record(.init(
                kind: "accepted_word_promoted",
                mode: "bilingual",
                reason: "word was typed repeatedly without conversion",
                bundleID: bundleID,
                sourceLayoutID: layoutID,
                original: word,
                contextBefore: contextHistory.getWords(),
                learnedWordCount: outcome.count
            ))
        }
    }

    private func recordReplacementForUndo(
        mode: String,
        reason: String,
        original: String,
        replacement: String,
        boundary: String,
        bundleID: String?,
        originalLayoutID: String?,
        targetLayoutID: String?,
        contextBefore: [String]
    ) {
        _lastReplacement = LastReplacementInfo(
            mode: mode,
            reason: reason,
            original: original,
            replacement: replacement,
            boundary: boundary,
            timestamp: Date(),
            bundleID: bundleID,
            originalLayoutID: originalLayoutID,
            targetLayoutID: targetLayoutID,
            isActive: true,
            boundaryBackspaceConsumed: false
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
            replacementAgeLimit: _smartBilingualUndoDelay,
            contextBefore: contextBefore
        ))
    }

    private func markReplacementBoundaryBackspaceConsumed(
        _ last: LastReplacementInfo,
        elapsed: Double,
        keyCode: Int64
    ) {
        var updated = last
        updated.boundaryBackspaceConsumed = true
        updated.timestamp = Date()
        _lastReplacement = updated

        SmartInputEventLog.shared.record(.init(
            kind: "replacement_boundary_backspace",
            mode: last.mode,
            reason: "first backspace after replacement deletes boundary before undo",
            bundleID: last.bundleID,
            sourceLayoutID: last.originalLayoutID,
            targetLayoutID: last.targetLayoutID,
            original: last.original,
            replacement: last.replacement,
            boundary: last.boundary,
            keyCode: keyCode,
            bufferBefore: getBufferToken(),
            elapsedSinceReplacement: elapsed,
            replacementAgeLimit: _smartBilingualUndoDelay
        ))
    }

    private func performReplacementUndo(
        _ last: LastReplacementInfo,
        elapsed: Double,
        keyCode: Int64,
        deleteBoundary: Bool
    ) {
        deactivateLastReplacement()
        recordRejectedConversionIfNeeded(last)
        
        let charsToDeleteCount = last.replacement.count + (deleteBoundary ? last.boundary.count : 0)
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
            replacementAgeLimit: _smartBilingualUndoDelay,
            suppressionReason: "learned_user_rejection"
        ))
    }

    private func recordRejectedConversionIfNeeded(_ last: LastReplacementInfo) {
        guard last.mode != "snippet" else {
            return
        }
        learningStore.recordRejectedConversion(
            mode: last.mode,
            original: last.original,
            replacement: last.replacement,
            sourceLayoutID: last.originalLayoutID,
            targetLayoutID: last.targetLayoutID,
            bundleID: last.bundleID
        )
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

    // MARK: - Spelling Autocorrect helpers
    
    public func isMisspelled(_ word: String, language: String, layoutID: String?) -> Bool {
        if word.count <= 1 {
            return false
        }
        
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 1. Check if word is accepted in our learning store
        if learningStore.isWordAccepted(normalized) {
            return false
        }
        
        // 2. Check common short words list
        if language == "en" && commonEnglishShortWords.contains(normalized) {
            return false
        }
        if language == "ru" && commonRussianShortWords.contains(normalized) {
            return false
        }
        
        // 3. Check spell checker
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location != NSNotFound
    }
    
    public func suggestionsForWord(_ word: String, language: String) -> [String] {
        let range = NSRange(location: 0, length: word.utf16.count)
        return checker.guesses(forWordRange: range, in: word, language: language, inSpellDocumentWithTag: 0) ?? []
    }
    
    private func replaceAutoCorrectedWord(original: String, autocorrected: String, replacement: String, boundary: String) {
        let charsToDeleteCount = autocorrected.count + boundary.count
        for _ in 0..<charsToDeleteCount {
            postKey(51) // Backspace
        }
        postText(replacement + boundary)
        
        if let last = getLastReplacement() {
            recordReplacementForUndo(
                mode: last.mode,
                reason: "user selected alternative suggestion '\(replacement)'",
                original: original,
                replacement: replacement,
                boundary: boundary,
                bundleID: last.bundleID,
                originalLayoutID: last.originalLayoutID,
                targetLayoutID: last.targetLayoutID,
                contextBefore: getContextHistoryWords()
            )
        }
    }
}

public struct SpellingSuggestionContext: Sendable {
    public let originalWord: String
    public let suggestions: [String]
    public let selectCallback: @Sendable (String) -> Void
    
    public init(originalWord: String, suggestions: [String], selectCallback: @escaping @Sendable (String) -> Void) {
        self.originalWord = originalWord
        self.suggestions = suggestions
        self.selectCallback = selectCallback
    }
}
