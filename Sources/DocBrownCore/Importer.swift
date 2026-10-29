import Foundation
import CryptoKit

public actor TranscriptImporter {
    public let store: HistoryStore
    private var repositories: [String: RepositoryContext] = [:]
    private var missingRepositories: Set<String> = []
    public init(store: HistoryStore) { self.store = store }

    public func scan(roots: [URL], excluded: [String] = [], progress: (@Sendable (ImportReport) -> Void)? = nil) async -> ImportReport {
        var report = ImportReport()
        var files: [(URL, Agent)] = []
        for root in roots {
            if root.pathExtension == "jsonl" { files.append((root, root.path.contains("claude") ? .claude : .codex)); continue }
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: { url, _ in
                return true
            }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if url.pathExtension == "jsonl" { files.append((url, root.path.lowercased().contains("claude") ? .claude : .codex)) }
            }
        }
        // Show useful recent history first during a long initial backfill.
        files.sort { $0.0.lastPathComponent > $1.0.lastPathComponent }
        for (url, inferredAgent) in files {
            if Task.isCancelled { break }
            do {
                let added = try importFile(url, inferredAgent: inferredAgent, excluded: excluded)
                report.messages += added; report.files += 1; report.latestFile = url.lastPathComponent
                if let row = try store.rows("SELECT malformed FROM sources WHERE path=?", [url.path]).first, let count = Int(row["malformed"] ?? "0"), count > 0, report.errors.count < 30 {
                    report.errors.append("\(url.lastPathComponent): \(count) malformed records preserved in the raw archive.")
                }
            } catch is CancellationError { break }
            catch {
                if report.errors.count < 30 { report.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            progress?(report)
            await Task.yield()
        }
        do { try ingestHookEvents(excluded: excluded) }
        catch { report.errors.append("Git context: \(error.localizedDescription)") }
        return report
    }

    private func importFile(_ url: URL, inferredAgent: Agent, excluded: [String]) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let saved = try store.rows("SELECT * FROM sources WHERE path=?", [url.path]).first
        var offset = Int64(saved?["offset"] ?? "0") ?? 0
        if offset == -1 { return 0 }
        let headerHandle = try FileHandle(forReadingFrom: url)
        var headerData = Data()
        while headerData.count < 4_000_000, let part = try headerHandle.read(upToCount: 32_768), !part.isEmpty {
            headerData.append(part)
            if let newline = headerData.firstIndex(of: 10) { headerData = Data(headerData[..<newline]); break }
        }
        try headerHandle.close()
        let headerObject = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any] ?? [:]
        let headerAgent: Agent = headerObject["sessionId"] != nil || ["user", "assistant"].contains(headerObject["type"] as? String ?? "") ? .claude : inferredAgent
        let header = try? TranscriptParser.parse(headerData, agent: headerAgent)
        let sourceKind = header?.sourceKind.isEmpty == false ? header!.sourceKind : "user"
        if let existingID = saved?["session_id"] {
            try store.execute("UPDATE sessions SET source_kind=? WHERE id=?", [sourceKind, existingID])
            if let current = try store.rows("SELECT title FROM sessions WHERE id=?", [existingID]).first?["title"], TranscriptParser.displayTitle(current) == nil || current.isEmpty {
                let prompts = try store.rows("SELECT body FROM messages WHERE session_id=? AND role='user' ORDER BY timestamp,source_line LIMIT 20", [existingID])
                if let title = prompts.compactMap({ TranscriptParser.displayTitle($0["body"] ?? "") }).first {
                    try store.execute("UPDATE sessions SET title=? WHERE id=?", [title, existingID])
                }
            }
        }
        if let id = saved?["session_id"], let existing = try store.session(id), excluded.contains(where: { Self.contains(path: existing.cwd, root: $0) }) {
            try store.deleteSession(id); return 0
        }
        let fingerprint = try store.rows("SELECT * FROM source_fingerprints WHERE path=?", [url.path]).first
        let prefixReader = try FileHandle(forReadingFrom: url)
        let oldCount = Int(fingerprint?["bytes"] ?? "0") ?? 0
        let prefix = try prefixReader.read(upToCount: oldCount > 0 ? oldCount : 4096) ?? Data()
        try prefixReader.close()
        let prefixHash = SHA256.hash(data: prefix).map { String(format: "%02x", $0) }.joined()
        let rewritten = oldCount > 0 && fingerprint?["hash"] != prefixHash
        if !rewritten && size == offset && abs((Double(saved?["modified"] ?? "0") ?? 0) - modified) < 0.001 { return 0 }
        let fallback = inferredAgent.rawValue + ":" + url.deletingPathExtension().lastPathComponent
        var sessionID = saved?["session_id"] ?? fallback
        var lineNumber = Int(saved?["line"] ?? "0") ?? 0
        var malformed = Int(saved?["malformed"] ?? "0") ?? 0
        let rawName = saved?["raw_name"] ?? SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined() + ".jsonl"
        let archiveURL = store.paths.raw.appendingPathComponent(rawName)
        // Rewritten sources keep the previous raw generation for audit; normalize the new generation afresh.
        if rewritten || size < offset || (size == offset && abs((Double(saved?["modified"] ?? "0") ?? 0) - modified) >= 0.001) {
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                try FileManager.default.moveItem(at: archiveURL, to: archiveURL.appendingPathExtension(UUID().uuidString + ".previous"))
            }
            try store.execute("DELETE FROM messages WHERE source_path=?", [url.path])
            try store.execute("DELETE FROM associations WHERE session_id=?", [sessionID])
            try store.execute("UPDATE sessions SET title='',cwd='',repository='',remote='',branch='',head='',model='',started='',updated='' WHERE id=?", [sessionID])
            offset = 0; lineNumber = 0; malformed = 0
        }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        try input.seek(toOffset: UInt64(offset))
        if !FileManager.default.fileExists(atPath: archiveURL.path) {
            if offset > 0 { // Restore a removed raw copy without losing its prefix.
                try FileManager.default.copyItem(at: url, to: archiveURL)
            } else { FileManager.default.createFile(atPath: archiveURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        }
        let archive = try FileHandle(forWritingTo: archiveURL)
        defer { try? archive.close() }
        try archive.truncate(atOffset: UInt64(offset))
        try archive.seek(toOffset: UInt64(offset))
        var session = try store.session(sessionID)
        var currentModel = session?.model ?? ""
        var currentCWD = session?.cwd ?? ""
        var currentBranch = session?.branch ?? ""
        var currentHead = session?.head ?? ""
        var currentRemote = session?.remote ?? ""
        var currentRepo = session?.repository ?? ""
        var title = session?.title ?? ""
        var started = session?.started ?? ""
        var updated = session?.updated ?? ""
        var agent = session.flatMap { Agent(rawValue: $0.agent) } ?? headerAgent
        var totalAdded = 0
        var buffer = Data()
        var batchRaw = Data()
        var batch: [(ParsedRecord, Int)] = []
        func flush() throws {
            guard !batchRaw.isEmpty else { return }
            try archive.write(contentsOf: batchRaw)
            try archive.synchronize()
            try store.transaction {
                for (record, line) in batch {
                    if !record.sessionID.isEmpty { sessionID = agent.rawValue + ":" + record.sessionID }
                    if !record.cwd.isEmpty { currentCWD = record.cwd }
                    if !record.model.isEmpty { currentModel = record.model }
                    if !record.branch.isEmpty { currentBranch = record.branch }
                    if !record.head.isEmpty { currentHead = record.head }
                    if !record.remote.isEmpty { currentRemote = record.remote }
                    if !currentCWD.isEmpty && currentRepo.isEmpty {
                        if let context = repositories[currentCWD] { currentRepo = context.root; if currentRemote.isEmpty { currentRemote = context.remote } }
                    }
                    if !record.timestamp.isEmpty {
                        if started.isEmpty || record.timestamp < started { started = record.timestamp }
                        if record.timestamp > updated { updated = record.timestamp }
                    }
                    if title.isEmpty, let candidate = record.messages.filter({ $0.role == "user" }).compactMap({ TranscriptParser.displayTitle($0.body) }).first {
                        title = candidate
                    }
                    try store.execute("""
                    INSERT INTO sessions(id,agent,title,cwd,repository,remote,branch,head,model,started,updated) VALUES(?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET title=CASE WHEN sessions.title='' THEN excluded.title ELSE sessions.title END,
                    cwd=excluded.cwd,repository=excluded.repository,remote=excluded.remote,branch=excluded.branch,head=excluded.head,model=excluded.model,
                    started=CASE WHEN sessions.started='' OR excluded.started<sessions.started THEN excluded.started ELSE sessions.started END,
                    updated=MAX(sessions.updated,excluded.updated)
                    """, [sessionID, agent.rawValue, title, currentCWD, currentRepo, currentRemote, currentBranch, currentHead, currentModel, started, updated])
                    try store.execute("UPDATE sessions SET source_kind=? WHERE id=? AND source_kind<>?", [sourceKind, sessionID, sourceKind])
                    if !record.callID.isEmpty, !record.command.isEmpty {
                        try store.execute("INSERT OR REPLACE INTO tool_commands VALUES(?,?,?)", [sessionID,record.callID,Self.isCommitCommand(record.command) ? 1 : 0])
                    }
                    let commitOutput = try record.isToolOutput && !record.callID.isEmpty && (try store.rows("SELECT commit_command FROM tool_commands WHERE session_id=? AND call_id=?", [sessionID,record.callID]).first?["commit_command"] == "1")
                    for (index, message) in record.messages.enumerated() {
                        let identity = message.identity.isEmpty ? "line:\(line):\(index)" : message.identity
                        let id = sessionID + ":" + identity
                        totalAdded += try store.execute("INSERT OR IGNORE INTO messages VALUES(?,?,?,?,?,?,?,?,?)", [id, sessionID, message.role, message.body, record.timestamp, currentModel, message.tool, url.path, line])
                        try captureEvidence(body: message.body, role: message.role, tool: message.tool, sessionID: sessionID, cwd: currentCWD, commitOutput: commitOutput)
                    }
                }
                offset += Int64(batchRaw.count)
                let hashBytes = min(4096, Int(offset))
                if hashBytes > 0 {
                    let h = try FileHandle(forReadingFrom: url)
                    defer { try? h.close() }
                    let prefixData = try h.read(upToCount: hashBytes) ?? Data()
                    let hash = SHA256.hash(data: prefixData).map { String(format: "%02x", $0) }.joined()
                    try store.execute("INSERT OR REPLACE INTO source_fingerprints VALUES(?,?,?)", [url.path, hashBytes, hash])
                }
                try store.execute("INSERT INTO sources VALUES(?,?,?,?,?,?,?) ON CONFLICT(path) DO UPDATE SET session_id=excluded.session_id,offset=excluded.offset,line=excluded.line,modified=excluded.modified,malformed=excluded.malformed", [url.path, sessionID, offset, lineNumber, modified, rawName, malformed])
            }
            batch.removeAll(keepingCapacity: true); batchRaw.removeAll(keepingCapacity: true)
        }
        while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            buffer.append(chunk)
            var consumed = buffer.startIndex
            while let newline = buffer[consumed...].firstIndex(of: 10) {
                let end = buffer.index(after: newline)
                let lineData = Data(buffer[consumed..<newline])
                if lineData.isEmpty {
                    batchRaw.append(buffer[consumed..<end]); consumed = end; continue
                }
                lineNumber += 1
                // Detect the provider from the record rather than relying on custom folder names.
                if lineNumber == 1, let object = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] {
                    if object["type"] as? String == "session_meta" { agent = .codex }
                    else if object["sessionId"] != nil || object["type"] as? String == "user" { agent = .claude }
                }
                do {
                    let record = try TranscriptParser.parse(lineData, agent: agent)
                    if !record.cwd.isEmpty {
                        if excluded.contains(where: { Self.contains(path: record.cwd, root: $0) }) {
                            try? FileManager.default.removeItem(at: archiveURL)
                            if let existing = saved?["session_id"] { try store.deleteSession(existing) }
                            return 0
                        }
                        if repositories[record.cwd] == nil && !missingRepositories.contains(record.cwd) {
                            if let context = GitContext.resolve(record.cwd) { repositories[record.cwd] = context }
                            else { missingRepositories.insert(record.cwd) }
                        }
                    }
                    batch.append((record, lineNumber))
                } catch { malformed += 1 }
                batchRaw.append(buffer[consumed..<end]); consumed = end
                if batchRaw.count > 2 * 1024 * 1024 || batch.count >= 150 { try flush() }
            }
            if consumed > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<consumed) }
        }
        // Import a complete final JSON record even without a newline. Invalid partial records
        // stay unconsumed so an active agent can finish them on the next scan.
        if !buffer.isEmpty, let record = try? TranscriptParser.parse(buffer, agent: agent) {
            lineNumber += 1
            batch.append((record, lineNumber)); batchRaw.append(buffer)
        }
        try flush()
        session = nil
        return totalAdded
    }

    private func ingestHookEvents(excluded: [String]) throws {
        let directory = store.paths.directory.appendingPathComponent("HookEvents")
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent
            if !(try store.rows("SELECT id FROM git_observations WHERE id=?", [id])).isEmpty { continue }
            guard let data = try? Data(contentsOf: file), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = event["session_id"] as? String, let session = try store.session(sessionID) else { continue }
            if excluded.contains(where: { Self.contains(path: session.cwd, root: $0) }) { continue }
            let branch = event["branch"] as? String ?? "", head = event["head"] as? String ?? ""
            try store.transaction {
                try store.execute("INSERT OR IGNORE INTO git_observations VALUES(?,?,?,?,?,?,?)", [id,sessionID,event["timestamp"] as? String ?? "",branch,head,event["files"] as? String ?? "",file.path])
                try store.execute("UPDATE sessions SET branch=CASE WHEN branch='' THEN ? ELSE branch END,head=CASE WHEN head='' THEN ? ELSE head END,repository=CASE WHEN repository='' THEN ? ELSE repository END,remote=CASE WHEN remote='' THEN ? ELSE remote END WHERE id=?", [branch,head,event["repository"] as? String ?? "",event["remote"] as? String ?? "",sessionID])
                if !head.isEmpty {
                    try store.addAssociation(sessionID: sessionID, kind: "snapshot", value: head, title: String(head.prefix(12)), confidence: "Observed", evidence: "HEAD and branch '\(branch)' observed by the local hook at \(event["timestamp"] as? String ?? ""). This snapshot alone does not prove the session created this commit.")
                }
            }
        }
    }

    private static func contains(path: String, root: String) -> Bool {
        let normalized = URL(fileURLWithPath: root).standardizedFileURL.path
        return path == normalized || path.hasPrefix(normalized + "/")
    }

    static func isCommitCommand(_ value: String) -> Bool {
        var command = value
        if let data = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            command = object["cmd"] as? String ?? object["command"] as? String ?? ""
        }
        let pattern = #"(?:^|[;\n&|])\s*(?:/usr/bin/)?git\s+(?:(?:-C|-c|--git-dir|--work-tree)\s+(?:"[^"]+"|'[^']+'|\S+)\s+)*commit(?:\s|$)"#
        return command.range(of: pattern, options: .regularExpression) != nil
    }

    private func captureEvidence(body: String, role: String, tool: String, sessionID: String, cwd: String, commitOutput: Bool) throws {
        // A mentioned PR is a reference, not proof of authorship or contribution.
        let pattern = #"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+"#
        let regex = try NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let range = Range(match.range, in: body) else { continue }
            let url = String(body[range])
            try store.addAssociation(sessionID: sessionID, kind: "pr", value: url, title: "PR #" + (url.split(separator: "/").last.map(String.init) ?? ""), confidence: "Referenced", evidence: "This PR URL appears in the transcript. A reference alone does not establish contribution.", url: url)
        }
        guard role == "tool", tool == "Tool result", !cwd.isEmpty, commitOutput else { return }
        let commitRegex = try NSRegularExpression(pattern: #"\[[^\]\n]+ ([0-9a-f]{7,40})\]"#)
        for match in commitRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let range = Range(match.range(at: 1), in: body) else { continue }
            let hash = String(body[range])
            guard let full = LocalCommand.run("/usr/bin/git", ["-C", cwd, "rev-parse", "--verify", hash + "^{commit}"]), full.count == 40 else { continue }
            try store.addAssociation(sessionID: sessionID, kind: "commit", value: full, title: String(full.prefix(12)), confidence: "Confirmed", evidence: "Git commit output in a tool result reports this commit; it resolves in the local repository.")
        }
    }
}
