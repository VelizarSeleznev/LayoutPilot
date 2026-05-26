import AppKit
import Foundation
import CoreGraphics

public final class TranslationService: @unchecked Sendable {
    public static let shared = TranslationService()
    
    private let queue = DispatchQueue(label: "com.layoutpilot.translation", qos: .userInitiated)
    private var isTranslating = false
    
    private init() {}
    
    public func translateSelectedText(to language: String, endpointURL: String, model: String) {
        guard !isTranslating else {
            print("Translation already in progress, ignoring request.")
            return
        }
        isTranslating = true
        
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.isTranslating = false }
            
            print("Starting translation to \(language) using model \(model) at endpoint \(endpointURL)")
            
            // 1. Save original clipboard contents
            let pasteboard = NSPasteboard.general
            let originalString = pasteboard.string(forType: .string)
            let previousChangeCount = pasteboard.changeCount
            
            // 2. Simulate copy (Cmd + C)
            self.simulateCmdC()
            
            // Wait for clipboard to update with selection
            var textToTranslate: String? = nil
            for _ in 0..<15 {
                Thread.sleep(forTimeInterval: 0.02)
                if pasteboard.changeCount != previousChangeCount {
                    textToTranslate = pasteboard.string(forType: .string)
                    break
                }
            }
            
            // Fallback: if change count didn't trigger, try reading anyway
            if textToTranslate == nil {
                textToTranslate = pasteboard.string(forType: .string)
            }
            
            guard let text = textToTranslate, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("No text was selected/copied for translation.")
                // Restore original pasteboard
                if let originalString = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(originalString, forType: .string)
                }
                return
            }
            
            print("Text to translate captured: \"\(text.prefix(30))...\"")
            
            // 3. Perform translation request
            guard let translated = self.performTranslationRequest(
                text: text,
                targetLanguage: language,
                endpointURL: endpointURL,
                model: model
            ) else {
                print("Translation request failed.")
                // Restore original pasteboard
                if let originalString = originalString {
                    pasteboard.clearContents()
                    pasteboard.setString(originalString, forType: .string)
                }
                return
            }
            
            print("Translation succeeded: \"\(translated.prefix(30))...\"")
            
            // 4. Put translation in clipboard
            pasteboard.clearContents()
            pasteboard.setString(translated, forType: .string)
            
            // 5. Simulate paste (Cmd + V)
            self.simulateCmdV()
            
            // 6. Restore original pasteboard after short delay to allow system to paste
            Thread.sleep(forTimeInterval: 0.2)
            if let originalString = originalString {
                pasteboard.clearContents()
                pasteboard.setString(originalString, forType: .string)
                print("Original clipboard restored.")
            }
        }
    }
    
    private func simulateCmdC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true) // 'c'
        let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    private func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // 'v'
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    private func performTranslationRequest(text: String, targetLanguage: String, endpointURL: String, model: String) -> String? {
        var urlString = endpointURL
        if !urlString.hasSuffix("/chat/completions") {
            if urlString.hasSuffix("/") {
                urlString += "chat/completions"
            } else if urlString.hasSuffix("/v1") {
                urlString += "/chat/completions"
            } else {
                urlString += "/v1/chat/completions"
            }
        }
        
        guard let url = URL(string: urlString) else {
            print("Invalid API URL: \(urlString)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25.0
        
        let prompt = "Translate the following text to \(targetLanguage). Output ONLY the translation. Do NOT add any explanations, notes, markdown formatting, or commentary. Preserve the original formatting, spacing, and tone. If the text is already in \(targetLanguage), output it exactly as is.\n\nText:\n\(text)"
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        request.httpBody = httpBody
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultText: String? = nil
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                print("Translation request error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received from translation endpoint.")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                resultText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                if let rawString = String(data: data, encoding: .utf8) {
                    print("Could not parse translation JSON. Raw response: \(rawString)")
                }
            }
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + 25.0)
        
        return resultText
    }
}
