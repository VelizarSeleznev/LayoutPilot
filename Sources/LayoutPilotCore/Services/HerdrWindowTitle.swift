import Darwin
import Foundation

/// Recognizes the title herdr writes to the terminal window it runs in.
///
/// herdr renders `[ui] window_title` from its config, a template whose tokens are `{hostname}`,
/// `{workspace}`, `{tab}`, `{pane}` and `{terminal_title}`, with `{{` and `}}` for literal braces.
/// `{hostname}` is known here, so it must match exactly; the other tokens follow herdr's live view
/// and match any text. A template with neither `{hostname}` nor visible literal text would match
/// arbitrary windows, and an empty one means herdr leaves the title alone; neither identifies
/// herdr, so both yield no matcher.
struct HerdrWindowTitleMatcher {
    /// herdr's default when the config does not set `window_title`.
    static let defaultTemplate = "{hostname}: {workspace}"

    let template: String
    let hostname: String
    private let expression: NSRegularExpression

    init?(template: String, hostname: String) {
        var pattern = "^"
        var literal = ""
        var identifies = false
        var index = template.startIndex

        func flushLiteral() {
            if literal.contains(where: { !$0.isWhitespace }) {
                identifies = true
            }
            pattern += NSRegularExpression.escapedPattern(for: literal)
            literal = ""
        }

        while index < template.endIndex {
            let rest = template[index...]
            if rest.hasPrefix("{{") {
                literal.append("{")
                index = template.index(index, offsetBy: 2)
            } else if rest.hasPrefix("}}") {
                literal.append("}")
                index = template.index(index, offsetBy: 2)
            } else if rest.first == "{", let close = rest.firstIndex(of: "}") {
                let token = template[template.index(after: index)..<close]
                switch token {
                case "hostname":
                    flushLiteral()
                    pattern += NSRegularExpression.escapedPattern(for: hostname)
                    identifies = true
                case "workspace", "tab", "pane", "terminal_title":
                    flushLiteral()
                    pattern += ".*"
                default:
                    literal += template[index...close]
                }
                index = template.index(after: close)
            } else {
                literal.append(template[index])
                index = template.index(after: index)
            }
        }
        flushLiteral()
        pattern += "$"

        guard identifies, let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        self.template = template
        self.hostname = hostname
        self.expression = expression
    }

    func matches(_ title: String) -> Bool {
        let range = NSRange(title.startIndex..., in: title)
        return expression.firstMatch(in: title, options: [], range: range) != nil
    }

    /// The host name herdr's local server renders for `{hostname}`.
    static func currentHostname() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        return String(cString: buffer)
    }
}

/// Reads the settings of herdr's `config.toml` that LayoutPilot depends on.
enum HerdrConfig {
    enum WindowTitle: Equatable {
        /// The config does not set it, so herdr uses its default.
        case unset
        case template(String)
        /// Set in a form this reader does not parse, so the template is unknown.
        case unreadable
    }

    /// `window_title` from the `[ui]` table.
    static func windowTitle(inTOML text: String) -> WindowTitle {
        var inUITable = false
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inUITable = tableName(line) == "ui"
                continue
            }
            guard inUITable, line.hasPrefix("window_title") else { continue }
            let afterKey = line.dropFirst("window_title".count).drop(while: { $0 == " " || $0 == "\t" })
            guard afterKey.first == "=" else { continue }
            let value = afterKey.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
            guard let parsed = parseString(value) else { return .unreadable }
            return .template(parsed)
        }
        return .unset
    }

    /// `ui` for `[ui]`; `nil` for arrays of tables such as `[[keys.command]]`.
    private static func tableName(_ header: String) -> String? {
        guard !header.hasPrefix("[["), let close = header.firstIndex(of: "]") else { return nil }
        return header[header.index(after: header.startIndex)..<close].trimmingCharacters(in: .whitespaces)
    }

    /// A single-line basic (`"…"`) or literal (`'…'`) TOML string followed by nothing but a comment.
    private static func parseString(_ value: Substring) -> String? {
        guard let quote = value.first, quote == "\"" || quote == "'" else { return nil }
        if value.hasPrefix(String(repeating: quote, count: 3)) { return nil }
        var result = ""
        var index = value.index(after: value.startIndex)
        while index < value.endIndex {
            let character = value[index]
            if character == quote {
                let rest = value[value.index(after: index)...].trimmingCharacters(in: .whitespaces)
                return rest.isEmpty || rest.hasPrefix("#") ? result : nil
            }
            if quote == "\"", character == "\\" {
                index = value.index(after: index)
                guard index < value.endIndex else { return nil }
                switch value[index] {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "b": result.append("\u{08}")
                case "t": result.append("\t")
                case "n": result.append("\n")
                case "f": result.append("\u{0C}")
                case "r": result.append("\r")
                case "e": result.append("\u{1B}")
                case "u", "U":
                    let length = value[index] == "u" ? 4 : 8
                    let start = value.index(after: index)
                    guard let end = value.index(start, offsetBy: length, limitedBy: value.endIndex),
                          let scalar = UInt32(value[start..<end], radix: 16).flatMap(Unicode.Scalar.init) else {
                        return nil
                    }
                    result.unicodeScalars.append(scalar)
                    index = value.index(before: end)
                default:
                    return nil
                }
            } else {
                result.append(character)
            }
            index = value.index(after: index)
        }
        return nil
    }
}
