import LayoutPilotCore
import SwiftUI

struct TranslationSettingsView: View {
    @Bindable var appState: LayoutPilotAppState
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestState = .untested
    
    enum ConnectionTestState {
        case untested
        case success(String)
        case failure(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Banner
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "translate")
                            .font(.system(size: 32))
                            .foregroundStyle(LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        
                        Text("LLM Translation")
                            .font(.system(.title, design: .rounded).weight(.bold))
                    }
                    
                    Text("Translate selected text instantly in any application using a local Large Language Model (LM Studio). Works fully offline with in-place text replacement.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                }
                .padding(.bottom, 4)
                
                // Master Enable Toggle Card
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Global LLM Translation")
                                .font(.headline)
                            Text("When enabled, global key combinations will intercept text and replace it with translations.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { appState.store.configuration.llm.translationEnabled ?? true },
                            set: { appState.store.setTranslationEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                if appState.store.configuration.llm.translationEnabled ?? true {
                    // Configuration Card
                    VStack(alignment: .leading, spacing: 20) {
                        Text("LM Studio Connection Settings")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Local API Endpoint")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                TextField("e.g. http://127.0.0.1:1234/v1", text: Binding(
                                    get: { appState.store.configuration.llm.endpointURL },
                                    set: { appState.store.setLLMEndpointURL($0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Model Name")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                TextField("e.g. google/gemma-4-e4b", text: Binding(
                                    get: { appState.store.configuration.llm.model },
                                    set: { appState.store.setLLMModel($0) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            }
                        }
                        
                        // Connection Tester
                        HStack(spacing: 12) {
                            Button {
                                testLLMConnection()
                            } label: {
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.trailing, 4)
                                }
                                Text("Test LM Studio Connection")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTestingConnection)
                            
                            switch connectionTestResult {
                            case .untested:
                                EmptyView()
                            case .success(let modelName):
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Connected! Model: \(modelName)")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            case .failure(let error):
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text("Failed: \(error)")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    
                    // Languages Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Global Language Shortcuts")
                            .font(.headline)
                        
                        Text("Configure which target languages are enabled. Highlight some text in any app and press the shortcut to translate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        
                        let langs = appState.store.configuration.llm.translationLanguages ?? []
                        
                        VStack(spacing: 12) {
                            ForEach(langs) { lang in
                                HStack {
                                    // Language Icon & Title
                                    HStack(spacing: 10) {
                                        Image(systemName: "character.bubble.fill")
                                            .font(.title3)
                                            .foregroundStyle(lang.isEnabled ? .blue : .secondary)
                                            .frame(width: 24)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(lang.name)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(lang.isEnabled ? .primary : .secondary)
                                            Text("Code: \(lang.code.uppercased())")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Keyboard Shortcut Pill
                                    HStack(spacing: 3) {
                                        Text("⌥ Option")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        Text("+")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("⇧ Shift")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        Text("+")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(lang.shortcutKey)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color(NSColor.windowBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                    )
                                    .opacity(lang.isEnabled ? 1.0 : 0.5)
                                    
                                    // Toggle switch
                                    Toggle("", isOn: Binding(
                                        get: { lang.isEnabled },
                                        set: { newValue in
                                            var updatedLangs = langs
                                            if let idx = updatedLangs.firstIndex(where: { $0.code == lang.code }) {
                                                updatedLangs[idx].isEnabled = newValue
                                                appState.store.setTranslationLanguages(updatedLangs)
                                            }
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .padding(.leading, 12)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(lang.isEnabled ? Color.primary.opacity(0.02) : Color.clear)
                                .cornerRadius(8)
                                
                                if lang.id != langs.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    
                    // Instructions Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to use LLM Translation:")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("1.")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.purple)
                                Text("Highlight/select any text in any macOS application (e.g. browser, editor).")
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("2.")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.purple)
                                Text("Press the global shortcut (e.g. **⌥ + ⇧ + R** to translate to Russian).")
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Text("3.")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.purple)
                                Text("LayoutPilot automatically runs local model inference and replaces your highlighted text in-place!")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [.purple.opacity(0.05), .blue.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(LinearGradient(
                                colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ), lineWidth: 1)
                    )
                }
            }
            .padding(.trailing, 4) // Spacing for ScrollView track
        }
    }
    
    private func testLLMConnection() {
        isTestingConnection = true
        connectionTestResult = .untested
        
        let endpoint = appState.store.configuration.llm.endpointURL
        var urlString = endpoint
        if !urlString.hasSuffix("/models") {
            if urlString.hasSuffix("/") {
                urlString += "models"
            } else if urlString.hasSuffix("/v1") {
                urlString += "/models"
            } else {
                urlString += "/v1/models"
            }
        }
        
        guard let url = URL(string: urlString) else {
            isTestingConnection = false
            connectionTestResult = .failure("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isTestingConnection = false
                if let error = error {
                    self.connectionTestResult = .failure(error.localizedDescription)
                    return
                }
                
                guard let data = data else {
                    self.connectionTestResult = .failure("No data received")
                    return
                }
                
                // Parse models
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]],
                   let firstModel = dataArray.first,
                   let modelName = firstModel["id"] as? String {
                    self.connectionTestResult = .success(modelName)
                } else {
                    self.connectionTestResult = .success(self.appState.store.configuration.llm.model)
                }
            }
        }.resume()
    }
}
