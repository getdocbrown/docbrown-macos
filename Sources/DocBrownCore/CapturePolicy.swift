import Foundation
import CSQLite

/// Shared with the short-lived hook helper, including when the UI is closed.
public enum CapturePolicy {
    public static func saveExclusions(_ pathsToExclude: [String], paths: LibraryPaths) throws {
        let data = try JSONSerialization.data(withJSONObject: pathsToExclude)
        let url = paths.directory.appendingPathComponent("exclusions.json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func permits(sessionID: String, cwd: String, paths: LibraryPaths) -> Bool {
        if let data = try? Data(contentsOf: paths.directory.appendingPathComponent("exclusions.json")), let roots = try? JSONSerialization.jsonObject(with: data) as? [String] {
            for root in roots {
                let normalized = URL(fileURLWithPath: root).standardizedFileURL.path
                if cwd == normalized || cwd.hasPrefix(normalized + "/") { return false }
            }
        }
        guard FileManager.default.fileExists(atPath: paths.database.path) else { return true }
        var db: OpaquePointer?
        guard sqlite3_open_v2(paths.database.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return false
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sources WHERE session_id=? AND offset=-1 LIMIT 1", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, sessionID, -1, transient)
        return sqlite3_step(statement) == SQLITE_DONE
    }
}
