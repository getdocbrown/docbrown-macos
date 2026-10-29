import Foundation

/// Provider records remain in the raw archive, including fields this version does not understand.
public enum TranscriptParser {
    public static func parse(_ data: Data, agent: Agent) throws -> ParsedRecord {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ParsedRecord() }
        return agent == .codex ? codex(object) : claude(object)
    }

    public static func displayTitle(_ body: String) -> String? {
        var value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = value.range(of: "## My request:") { value = String(value[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
        if value.hasPrefix("<") || value.hasPrefix("# Files ") || value.hasPrefix("## Referenced ChatGPT conversation:") { return nil }
        guard !value.isEmpty else { return nil }
        return String(value.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(160))
    }

    static func text(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let array = value as? [[String: Any]] {
            return array.compactMap { block -> String? in
                if let text = block["text"] as? String { return text }
                if block["type"] as? String == "image" || block["type"] as? String == "input_image" { return "[Image attachment]" }
                return nil
            }.joined(separator: "\n\n")
        }
        return ""
    }

    static func json(_ value: Any?) -> String {
        if let s = value as? String { return s }
        guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func codex(_ o: [String: Any]) -> ParsedRecord {
        var r = ParsedRecord()
        r.timestamp = o["timestamp"] as? String ?? ""
        let p = o["payload"] as? [String: Any] ?? [:]
        switch o["type"] as? String {
        case "session_meta":
            let source = p["source"] as? [String: Any] ?? [:]
            let subagent = source["subagent"] as? [String: Any] ?? [:]
            r.sourceKind = (p["thread_source"] as? String == "guardian_review" || subagent["other"] as? String == "guardian") ? "internal" : "user"
            r.sessionID = p["id"] as? String ?? p["session_id"] as? String ?? ""
            r.cwd = p["cwd"] as? String ?? ""
            let git = p["git"] as? [String: Any] ?? [:]
            r.branch = git["branch"] as? String ?? ""
            r.head = git["commit_hash"] as? String ?? ""
            r.remote = git["repository_url"] as? String ?? ""
            r.model = p["model"] as? String ?? ""
        case "turn_context":
            r.cwd = p["cwd"] as? String ?? ""
            r.model = p["model"] as? String ?? ""
        case "response_item":
            let type = p["type"] as? String ?? ""
            let identity = p["id"] as? String ?? ""
            if type == "message" {
                let role = p["role"] as? String ?? ""
                if role == "user" || role == "assistant" {
                    let body = text(p["content"])
                    if !body.isEmpty { r.messages.append((role, body, "", identity)) }
                }
            } else if type == "function_call" || type == "custom_tool_call" {
                r.callID = p["call_id"] as? String ?? ""
                r.command = json(p["arguments"] ?? p["input"])
                r.messages.append(("tool", json(p["arguments"] ?? p["input"]), p["name"] as? String ?? "Tool call", identity))
            } else if type == "function_call_output" || type == "custom_tool_call_output" {
                r.callID = p["call_id"] as? String ?? ""; r.isToolOutput = true
                r.messages.append(("tool", json(p["output"]), "Tool result", identity))
            }
        default: break // event_msg mirrors response_item; importing both would duplicate conversations.
        }
        return r
    }

    static func claude(_ o: [String: Any]) -> ParsedRecord {
        var r = ParsedRecord()
        r.sessionID = o["sessionId"] as? String ?? o["session_id"] as? String ?? ""
        r.cwd = o["cwd"] as? String ?? ""
        r.branch = o["gitBranch"] as? String ?? ""
        r.timestamp = o["timestamp"] as? String ?? ""
        let type = o["type"] as? String ?? ""
        guard type == "user" || type == "assistant" else { return r }
        let m = o["message"] as? [String: Any] ?? [:]
        r.model = m["model"] as? String ?? ""
        let identity = o["uuid"] as? String ?? ""
        if let content = m["content"] as? [[String: Any]] {
            for (i, block) in content.enumerated() {
                let blockID = identity.isEmpty ? "" : identity + ":\(i)"
                switch block["type"] as? String {
                case "tool_use":
                    r.callID = block["id"] as? String ?? ""; r.command = json(block["input"])
                    r.messages.append(("tool", json(block["input"]), block["name"] as? String ?? "Tool call", blockID))
                case "tool_result":
                    r.callID = block["tool_use_id"] as? String ?? ""; r.isToolOutput = true
                    r.messages.append(("tool", text(block["content"]), "Tool result", blockID))
                case "text":
                    if let body = block["text"] as? String, !body.isEmpty { r.messages.append((type, body, "", blockID)) }
                case "image": r.messages.append((type, "[Image attachment]", "", blockID))
                default: break
                }
            }
        } else if let body = m["content"] as? String, !body.isEmpty {
            r.messages.append((type, body, "", identity))
        }
        return r
    }
}
