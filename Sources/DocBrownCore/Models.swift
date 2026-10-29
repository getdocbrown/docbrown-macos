import Foundation

public enum Agent: String, CaseIterable, Codable, Sendable { case codex = "Codex", claude = "Claude Code" }

public struct Session: Identifiable, Sendable {
    public var id: String
    public var agent: String
    public var title: String
    public var cwd: String
    public var repository: String
    public var remote: String
    public var branch: String
    public var head: String
    public var model: String
    public var started: String
    public var updated: String
    public var messageCount: Int
    public var snippet: String
    public var projectName: String { URL(fileURLWithPath: repository.isEmpty ? cwd : repository).lastPathComponent }
}

public struct Message: Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var role: String
    public var body: String
    public var timestamp: String
    public var model: String
    public var tool: String
    public var sourcePath: String
    public var sourceLine: Int
}

public struct Association: Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var kind: String
    public var value: String
    public var title: String
    public var confidence: String
    public var evidence: String
    public var url: String
}

public struct ImportReport: Sendable {
    public var files = 0
    public var messages = 0
    public var errors: [String] = []
    public var latestFile = ""
    public init() {}
}

public struct ParsedRecord {
    public var sessionID = ""
    public var cwd = ""
    public var branch = ""
    public var head = ""
    public var remote = ""
    public var model = ""
    public var timestamp = ""
    public var sourceKind = ""
    public var callID = ""
    public var command = ""
    public var isToolOutput = false
    public var messages: [(role: String, body: String, tool: String, identity: String)] = []
    public init() {}
}

public struct LibraryPaths: Sendable {
    public var directory: URL
    public var database: URL { directory.appendingPathComponent("history.sqlite") }
    public var raw: URL { directory.appendingPathComponent("Transcripts", isDirectory: true) }
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DocBrown", isDirectory: true)
    }
    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let claude = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        return [codex.appendingPathComponent("sessions"), codex.appendingPathComponent("archived_sessions"), claude.appendingPathComponent("projects")]
    }
}
