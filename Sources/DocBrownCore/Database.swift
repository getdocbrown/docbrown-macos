import Foundation
import CSQLite

public struct DatabaseError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class HistoryStore: @unchecked Sendable {
    private var db: OpaquePointer?
    public let paths: LibraryPaths
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(paths: LibraryPaths = LibraryPaths()) throws {
        self.paths = paths
        try FileManager.default.createDirectory(at: paths.raw, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sqlite3_open_v2(paths.database.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw DatabaseError(message: "Cannot open local history database") }
        sqlite3_busy_timeout(db, 10000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA synchronous=NORMAL")
        let previousVersion = Int(try rows("PRAGMA user_version").first?["user_version"] ?? "0") ?? 0
        try execute("""
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY, agent TEXT NOT NULL, title TEXT NOT NULL DEFAULT '', cwd TEXT NOT NULL DEFAULT '',
          repository TEXT NOT NULL DEFAULT '', remote TEXT NOT NULL DEFAULT '', branch TEXT NOT NULL DEFAULT '',
          head TEXT NOT NULL DEFAULT '', model TEXT NOT NULL DEFAULT '', started TEXT NOT NULL DEFAULT '', updated TEXT NOT NULL DEFAULT '');
        CREATE TABLE IF NOT EXISTS sources (
          path TEXT PRIMARY KEY, session_id TEXT NOT NULL, offset INTEGER NOT NULL DEFAULT 0,
          line INTEGER NOT NULL DEFAULT 0, modified REAL NOT NULL DEFAULT 0, raw_name TEXT NOT NULL,
          malformed INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS tool_commands (session_id TEXT NOT NULL, call_id TEXT NOT NULL, commit_command INTEGER NOT NULL, PRIMARY KEY(session_id,call_id));
        CREATE TABLE IF NOT EXISTS git_observations (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL, timestamp TEXT NOT NULL, branch TEXT NOT NULL,
          head TEXT NOT NULL, files TEXT NOT NULL, source_path TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS source_fingerprints (path TEXT PRIMARY KEY, bytes INTEGER NOT NULL, hash TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          role TEXT NOT NULL, body TEXT NOT NULL, timestamp TEXT NOT NULL, model TEXT NOT NULL,
          tool TEXT NOT NULL, source_path TEXT NOT NULL, source_line INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS messages_session ON messages(session_id, timestamp, source_line);
        CREATE TABLE IF NOT EXISTS associations (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          kind TEXT NOT NULL, value TEXT NOT NULL, title TEXT NOT NULL, confidence TEXT NOT NULL,
          evidence TEXT NOT NULL, url TEXT NOT NULL DEFAULT '');
        CREATE INDEX IF NOT EXISTS associations_session ON associations(session_id);
        CREATE TABLE IF NOT EXISTS pull_requests (
          url TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, state TEXT NOT NULL,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, viewer TEXT NOT NULL,
          authored INTEGER NOT NULL DEFAULT 0, reviewed INTEGER NOT NULL DEFAULT 0, commented INTEGER NOT NULL DEFAULT 0);
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(body, content='messages', content_rowid='rowid', tokenize='unicode61');
        CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
          INSERT INTO messages_fts(rowid, body) VALUES (new.rowid, new.body); END;
        CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
          INSERT INTO messages_fts(messages_fts, rowid, body) VALUES('delete', old.rowid, old.body); END;
        CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
          INSERT INTO messages_fts(messages_fts, rowid, body) VALUES('delete', old.rowid, old.body);
          INSERT INTO messages_fts(rowid, body) VALUES(new.rowid, new.body); END;

        """)
        if !(try rows("PRAGMA table_info(sessions)")).contains(where: { $0["name"] == "source_kind" }) {
            try execute("ALTER TABLE sessions ADD COLUMN source_kind TEXT NOT NULL DEFAULT 'user'")
        }
        if previousVersion < 2 {
            try execute("UPDATE associations SET confidence='Inferred',evidence='Historical tool output; command/result pairing has not been verified.' WHERE confidence='Confirmed'")
            try execute("PRAGMA user_version=2")
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.database.path)
    }
    deinit { sqlite3_close(db) }

    @discardableResult public func execute(_ sql: String, _ values: [Any] = []) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        if values.isEmpty {
            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? "Database write failed"
                sqlite3_free(error); throw DatabaseError(message: message)
            }
        } else {
            let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        }
        return Int(sqlite3_changes(db))
    }
    private func failure() -> DatabaseError { DatabaseError(message: String(cString: sqlite3_errmsg(db))) }
    private func prepare(_ sql: String, _ values: [Any]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in values.enumerated() {
            let i = Int32(index + 1)
            if let v = value as? Int64 { sqlite3_bind_int64(statement, i, v) }
            else if let v = value as? Int { sqlite3_bind_int64(statement, i, Int64(v)) }
            else if let v = value as? Double { sqlite3_bind_double(statement, i, v) }
            else { sqlite3_bind_text(statement, i, String(describing: value), -1, transient) }
        }
        return statement
    }
    public func rows(_ sql: String, _ values: [Any] = []) throws -> [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        let s = try prepare(sql, values); defer { sqlite3_finalize(s) }
        var rows: [[String: String]] = []
        var status = sqlite3_step(s)
        while status == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(s) {
                let name = String(cString: sqlite3_column_name(s, i))
                row[name] = sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
            }
            rows.append(row); status = sqlite3_step(s)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return rows
    }
    public func transaction<T>(_ work: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do { let result = try work(); try execute("COMMIT"); return result }
        catch { _ = try? execute("ROLLBACK"); throw error }
    }
    public func session(_ id: String) throws -> Session? {
        try rows("SELECT s.*, (SELECT count(*) FROM messages WHERE session_id=s.id) AS message_count FROM sessions s WHERE id=?", [id]).first.map(decode)
    }
    private func decode(_ r: [String: String]) -> Session {
        Session(id: r["id"]!, agent: r["agent"]!, title: r["title"] ?? "", cwd: r["cwd"] ?? "", repository: r["repository"] ?? "", remote: r["remote"] ?? "", branch: r["branch"] ?? "", head: r["head"] ?? "", model: r["model"] ?? "", started: r["started"] ?? "", updated: r["updated"] ?? "", messageCount: Int(r["message_count"] ?? "0") ?? 0, snippet: r["snippet"] ?? "")
    }
    public func search(_ query: String = "", agent: String = "", repository: String = "", limit: Int = 200, offset: Int = 0, includeInternal: Bool = false, rankByRelevance: Bool = false, projectRoots: [String] = []) throws -> [Session] {
        var predicates = ["EXISTS (SELECT 1 FROM messages WHERE session_id=s.id)"]
        var values: [Any] = []
        var selectValues: [Any] = []
        if !includeInternal { predicates.append("s.source_kind<>'internal'") }
        if !agent.isEmpty { predicates.append("s.agent=?"); values.append(agent) }
        if !repository.isEmpty {
            let roots = projectRoots.isEmpty ? [repository] : projectRoots
            var scopes: [String] = []
            for root in roots {
                let path = URL(fileURLWithPath: root).standardizedFileURL.path
                let escaped = path.replacingOccurrences(of: "!", with: "!!").replacingOccurrences(of: "%", with: "!%").replacingOccurrences(of: "_", with: "!_")
                let children = (escaped == "/" ? "/" : escaped + "/") + "%"
                scopes.append("(s.repository=? OR s.cwd=? OR s.repository LIKE ? ESCAPE '!' OR s.cwd LIKE ? ESCAPE '!')")
                values.append(contentsOf: [path, path, children, children])
            }
            predicates.append("(" + scopes.joined(separator: " OR ") + ")")
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = text.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var snippet = "'' AS snippet"
        var ranking = ""
        var prefix = ""
        var joins = ""
        var order = "s.updated DESC, s.id ASC"
        if !terms.isEmpty {
            // Treat user input as literal tokens: punctuation and quotes can never execute FTS syntax.
            let match = terms.joined(separator: " AND ")
            // Rank matching passages once for the whole query, rather than rescanning
            // the full-text index separately for every conversation.
            prefix = """
            WITH search_hits AS MATERIALIZED (
              SELECT m.session_id, m.rowid AS message_rowid, rank AS relevance
              FROM messages_fts JOIN messages m ON m.rowid=messages_fts.rowid WHERE messages_fts MATCH ?
            ), best_hits AS (
              SELECT session_id,message_rowid,relevance FROM (
                SELECT *, ROW_NUMBER() OVER(PARTITION BY session_id ORDER BY relevance,message_rowid) AS position
                FROM search_hits
              ) WHERE position=1
            )
            """
            joins = "LEFT JOIN best_hits hits ON hits.session_id=s.id"
            snippet = "COALESCE((SELECT snippet(messages_fts,0,'','', ' … ',32) FROM messages_fts WHERE messages_fts MATCH ? AND messages_fts.rowid=hits.message_rowid),'') AS snippet"
            selectValues.append(contentsOf: [match, match])
            predicates.append("""
            (hits.session_id IS NOT NULL
            OR s.title LIKE ? ESCAPE '!' OR s.cwd LIKE ? ESCAPE '!' OR s.repository LIKE ? ESCAPE '!' OR s.branch LIKE ? ESCAPE '!' OR s.head LIKE ? ESCAPE '!'
            OR s.id IN (SELECT session_id FROM associations WHERE value LIKE ? ESCAPE '!' OR url LIKE ? ESCAPE '!'))
            """)
            let escaped = text.replacingOccurrences(of: "!", with: "!!").replacingOccurrences(of: "%", with: "!%").replacingOccurrences(of: "_", with: "!_")
            let like = "%" + escaped + "%"
            values.append(contentsOf: Array(repeating: like, count: 7))
            if rankByRelevance {
                // Prefer titles, then the best matching passage. Recency only breaks ties;
                // a long, active conversation should not outrank a more focused match.
                ranking = """
                , CASE WHEN s.title = ? COLLATE NOCASE THEN 0
                       WHEN s.title LIKE ? ESCAPE '!' THEN 1
                       WHEN s.title LIKE ? ESCAPE '!' THEN 2 ELSE 3 END AS title_priority,
                COALESCE(hits.relevance,0) AS relevance
                """
                selectValues.append(contentsOf: [text, escaped + "%", like])
                order = "title_priority ASC, relevance ASC, s.updated DESC, s.id ASC"
            }
        }
        values.append(limit); values.append(offset)
        return try rows("\(prefix) SELECT s.*, (SELECT count(*) FROM messages WHERE session_id=s.id) AS message_count, \(snippet) \(ranking) FROM sessions s \(joins) WHERE \(predicates.joined(separator: " AND ")) ORDER BY \(order) LIMIT ? OFFSET ?", selectValues + values).map(decode)
    }
    public func messages(_ sessionID: String, limit: Int = 250, offset: Int = 0) throws -> [Message] {
        try rows("SELECT * FROM messages WHERE session_id=? ORDER BY timestamp, source_path, source_line, rowid LIMIT ? OFFSET ?", [sessionID, limit, offset]).map { r in
            Message(id: r["id"]!, sessionID: r["session_id"]!, role: r["role"]!, body: r["body"]!, timestamp: r["timestamp"]!, model: r["model"]!, tool: r["tool"]!, sourcePath: r["source_path"]!, sourceLine: Int(r["source_line"]!) ?? 0)
        }
    }
    public func associations(_ sessionID: String? = nil, includeInternal: Bool = false) throws -> [Association] {
        try rows("SELECT * FROM associations" + (sessionID == nil ? " WHERE kind='pr'" + (includeInternal ? "" : " AND session_id IN (SELECT id FROM sessions WHERE source_kind<>'internal')") : " WHERE session_id=?") + " ORDER BY value", sessionID.map { [$0] } ?? []).map { r in
            Association(id: r["id"]!, sessionID: r["session_id"]!, kind: r["kind"]!, value: r["value"]!, title: r["title"]!, confidence: r["confidence"]!, evidence: r["evidence"]!, url: r["url"]!)
        }
    }
    public func addAssociation(sessionID: String, kind: String, value: String, title: String, confidence: String, evidence: String, url: String = "") throws {
        try execute("""
        INSERT INTO associations VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
        title=excluded.title,confidence=excluded.confidence,evidence=excluded.evidence,url=excluded.url
        WHERE (CASE excluded.confidence WHEN 'Confirmed' THEN 3 WHEN 'Inferred' THEN 2 ELSE 1 END)
        >= (CASE associations.confidence WHEN 'Confirmed' THEN 3 WHEN 'Inferred' THEN 2 ELSE 1 END)
        """, [sessionID + ":" + kind + ":" + value, sessionID, kind, value, title, confidence, evidence, url])
    }

    public func firstMatchOffset(_ sessionID: String, query: String) throws -> Int? {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
        guard !terms.isEmpty else { return nil }
        let row = try rows("""
        WITH ordered AS (
          SELECT id, row_number() OVER(ORDER BY timestamp,source_path,source_line,rowid)-1 AS position
          FROM messages WHERE session_id=?
        ) SELECT position FROM ordered WHERE id IN (
          SELECT m.id FROM messages_fts JOIN messages m ON m.rowid=messages_fts.rowid
          WHERE messages_fts MATCH ? AND m.session_id=?
        ) ORDER BY position LIMIT 1
        """, [sessionID, terms, sessionID]).first
        return row.flatMap { Int($0["position"] ?? "") }
    }

    public func repositories(includeInternal: Bool = false) throws -> [String] {
        try rows("""
        SELECT DISTINCT CASE WHEN repository<>'' THEN repository ELSE cwd END AS directory FROM sessions s
        WHERE (repository<>'' OR cwd<>'') \(includeInternal ? "" : "AND source_kind<>'internal'")
          AND EXISTS (SELECT 1 FROM messages WHERE session_id=s.id)
        ORDER BY directory
        """).compactMap { $0["directory"] }
    }
    public func counts(includeInternal: Bool = false) throws -> (sessions: Int, messages: Int) {
        let filter = includeInternal ? "1=1" : "source_kind<>'internal'"
        let r = try rows("SELECT (SELECT count(*) FROM sessions WHERE \(filter) AND EXISTS(SELECT 1 FROM messages WHERE session_id=sessions.id)) AS sessions, (SELECT count(*) FROM messages WHERE session_id IN (SELECT id FROM sessions WHERE \(filter))) AS messages")[0]
        return (Int(r["sessions"]!) ?? 0, Int(r["messages"]!) ?? 0)
    }
    public func deleteSession(_ id: String) throws {
        // Keep a tombstone in sources, so automatic collection respects the user's deletion.
        try transaction {
            let sources = try rows("SELECT raw_name FROM sources WHERE session_id=?", [id])
            let hookFiles = try rows("SELECT source_path FROM git_observations WHERE session_id=?", [id])
            try execute("DELETE FROM git_observations WHERE session_id=?", [id])
            try execute("DELETE FROM tool_commands WHERE session_id=?", [id])
            for file in hookFiles { try? FileManager.default.removeItem(atPath: file["source_path"]!) }
            try execute("DELETE FROM sessions WHERE id=?", [id])
            try execute("UPDATE sources SET offset=-1 WHERE session_id=?", [id])
            let rawFiles = (try? FileManager.default.contentsOfDirectory(at: paths.raw, includingPropertiesForKeys: nil)) ?? []
            for source in sources {
                let name = source["raw_name"]!
                for file in rawFiles where file.lastPathComponent == name || file.lastPathComponent.hasPrefix(name + ".") { try? FileManager.default.removeItem(at: file) }
            }
        }
    }
}
