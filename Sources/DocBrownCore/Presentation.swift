import Foundation

/// A reading projection only: imported messages and exports retain the original text.
public struct ReadingText: Equatable, Sendable {
    public let body: String
    public let context: String
    public var isContextOnly: Bool { body.isEmpty && !context.isEmpty }
    public init(_ original: String, extractContext: Bool = true) {
        guard extractContext else { body = original; context = ""; return }
        var body = original
        var context: [String] = []
        for tag in original.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") ? ["environment_context", "external_codex_apps_open_page", "user_instructions", "permissions", "collaboration_mode", "turn_aborted"] : [] {
            let pattern = "<" + tag + "(?:\\s[^>]*)?>[\\s\\S]*?</" + tag + ">"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).reversed() {
                guard let range = Range(match.range, in: body) else { continue }
                context.insert(String(body[range]), at: 0)
                body.removeSubrange(range)
            }
        }
        if let marker = body.range(of: "## My request:") {
            context.append(String(body[..<marker.lowerBound]))
            body = String(body[marker.upperBound...])
        }
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.context = context.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ReadingItem: Identifiable, Sendable {
    public enum Kind: Sendable { case message, activity, context }
    public let id: String
    public let kind: Kind
    public var messages: [Message]
    public static func build(_ messages: [Message]) -> [ReadingItem] {
        var items: [ReadingItem] = []
        for message in messages {
            let kind: Kind = message.role == "tool" ? .activity : ReadingText(message.body, extractContext: message.role == "user").isContextOnly ? .context : .message
            if kind != .message, items.last?.kind == kind { items[items.count - 1].messages.append(message) }
            else { items.append(ReadingItem(id: message.id, kind: kind, messages: [message])) }
        }
        return items
    }
}

public enum ToolReading {
    public static func text(_ raw: String, depth: Int = 0) -> String {
        guard depth < 3, raw.utf8.count < 500_000, let data = raw.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) else { return raw }
        if let array = value as? [[String: Any]] {
            let texts = array.compactMap { $0["text"] as? String }
            if !texts.isEmpty { return texts.map { text($0, depth: depth + 1) }.joined(separator: "\n") }
        }
        if let object = value as? [String: Any] {
            for key in ["cmd", "command", "code", "output"] { if let s = object[key] as? String { return text(s, depth: depth + 1) } }
            if let s = object["output"] as? [String: Any] { return text(TranscriptParser.json(s), depth: depth + 1) }
            if let s = object["text"] as? String { return text(s, depth: depth + 1) }
            if let s = object["content"] as? [[String: Any]] { return s.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        }
        return raw
    }
    public static func summary(_ message: Message) -> String {
        let content = text(message.body).trimmingCharacters(in: .whitespacesAndNewlines)
        let line = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? message.tool
        return String(line.prefix(150))
    }
}

public struct MarkdownBlock: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case paragraph, heading(Int), code(String), bullet(String), quote, rule, table([[String]]) }
    public var id: Int
    public var kind: Kind
    public var text: String
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraph: [String] = [], code: [String] = []
        var language: String? = nil
        func add(_ kind: Kind, _ text: String) { result.append(.init(id: result.count, kind: kind, text: text)) }
        func flush() {
            guard !paragraph.isEmpty else { return }
            if paragraph.count >= 2, paragraph[0].contains("|"), paragraph[1].contains("-"), paragraph[1].range(of: #"^[|:\-\s]+$"#, options: .regularExpression) != nil {
                let rows = [paragraph[0]] + Array(paragraph.dropFirst(2))
                let cells = rows.map { row -> [String] in
                    var parts = row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.first == "" { parts.removeFirst() }; if parts.last == "" { parts.removeLast() }
                    return parts
                }
                add(.table(cells), "")
            } else { add(.paragraph, paragraph.joined(separator: "\n")) }
            paragraph = []
        }
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let lang = language { add(.code(lang), code.joined(separator: "\n")); code = []; language = nil }
                else { flush(); language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if language != nil { code.append(line); continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }
            let hashes = line.prefix { $0 == "#" }.count
            if hashes > 0 && hashes <= 6 && line.dropFirst(hashes).hasPrefix(" ") { flush(); add(.heading(hashes), String(line.dropFirst(hashes + 1))); continue }
            if ["---", "***", "___"].contains(line) { flush(); add(.rule, ""); continue }
            if line.hasPrefix("> ") { flush(); add(.quote, String(line.dropFirst(2))); continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { flush(); add(.bullet("•"), String(trimmed.dropFirst(2))); continue }
            if let range = trimmed.range(of: #"^\d+\. "#, options: .regularExpression) { flush(); add(.bullet(String(trimmed[range]).trimmingCharacters(in: .whitespaces)), String(trimmed[range.upperBound...])); continue }
            paragraph.append(line)
        }
        flush()
        if let lang = language { add(.code(lang), code.joined(separator: "\n")) }
        return result
    }
}
