import Foundation

public enum HookProvider: String, CaseIterable, Sendable {
    case codex, claude
    public var name: String { self == .codex ? "Codex" : "Claude Code" }
    public func config(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if self == .codex {
            let folder = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
            return folder.appendingPathComponent("hooks.json")
        }
        let folder = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        return folder.appendingPathComponent("settings.json")
    }
}

public struct HookInstaller {
    public let paths: LibraryPaths
    public var helper: URL { paths.directory.appendingPathComponent("bin/docbrown") }
    public init(paths: LibraryPaths) { self.paths = paths }
    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public func command(_ provider: HookProvider) -> String { Self.shellQuote(helper.path) + " hook " + provider.rawValue }
    public func status(_ provider: HookProvider, config: URL? = nil) -> String {
        do {
            let config = config ?? provider.config()
            guard FileManager.default.fileExists(atPath: config.path) else { return "Not installed" }
            let object = try read(config)
            let hooks = object["hooks"] as? [String: Any] ?? [:]
            let all = hooks.values.compactMap { $0 as? [[String: Any]] }.flatMap { $0 }.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            return all.contains { $0["command"] as? String == command(provider) } ? "Configured · review in \(provider.name) to activate" : "Not installed"
        } catch { return "Cannot read configuration: \(error.localizedDescription)" }
    }
    private func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw DatabaseError(message: "Configuration is not a JSON object; it was left unchanged.") }
        if let value = object["hooks"], !(value is [String: Any]) { throw DatabaseError(message: "Unrecognized hooks format; configuration was left unchanged.") }
        return object
    }
    public func install(_ provider: HookProvider, bundledHelper: URL, config: URL? = nil) throws {
        let url = (config ?? provider.config()).resolvingSymlinksInPath()
        var object = try read(url)
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        for event in ["SessionStart", "PostToolUse", "Stop"] {
            if let value = hooks[event], !(value is [[String: Any]]) { throw DatabaseError(message: "Unrecognized \(event) configuration; no changes were made.") }
            var groups = hooks[event] as? [[String: Any]] ?? []
            let exists = groups.contains { group in (group["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command(provider) } }
            if !exists { groups.append(["hooks": [["type":"command", "command":command(provider), "timeout":5, "async":true]]]) }
            hooks[event] = groups
        }
        object["hooks"] = hooks
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The stable helper path survives moving the app bundle or an application update.
        let binary = try Data(contentsOf: bundledHelper)
        try binary.write(to: helper, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        try write(object, to: url)
    }
    public func uninstall(_ provider: HookProvider, config: URL? = nil) throws {
        let url = (config ?? provider.config()).resolvingSymlinksInPath()
        var object = try read(url)
        var hooks = object["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var group = group
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = handlers.filter { $0["command"] as? String != command(provider) }
                guard !remaining.isEmpty else { return nil }
                group["hooks"] = remaining; return group
            }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        object["hooks"] = hooks
        try write(object, to: url)
    }
    private func write(_ object: [String: Any], to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: url.path) {
            let backup = paths.directory.appendingPathComponent("Backups", isDirectory: true)
            try manager.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = backup.appendingPathComponent(url.lastPathComponent + "." + UUID().uuidString + ".backup")
            try manager.copyItem(at: url, to: file)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]); data.append(10)
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum HookCapture {
    public static let notification = Notification.Name("ai.docbrown.historyChanged")
    /// Hook inputs are data only. No transcript-provided shell command is ever evaluated.
    public static func capture(provider: HookProvider, input: Data, paths: LibraryPaths = LibraryPaths()) throws {
        guard input.count <= 2_000_000, let object = try JSONSerialization.jsonObject(with: input) as? [String: Any] else { return }
        let id = object["session_id"] as? String ?? object["thread_id"] as? String ?? object["thread-id"] as? String ?? ""
        let cwd = object["cwd"] as? String ?? ""
        guard !id.isEmpty, !cwd.isEmpty else { return }
        let directory = paths.directory.appendingPathComponent("HookEvents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var event: [String: Any] = ["id": UUID().uuidString, "session_id": (provider == .codex ? Agent.codex.rawValue : Agent.claude.rawValue) + ":" + id, "cwd": cwd, "timestamp": ISO8601DateFormatter().string(from: Date()), "event": object["hook_event_name"] as? String ?? "Activity"]
        if let context = GitContext.resolve(cwd) {
            event["repository"] = context.root; event["remote"] = context.remote
            event["branch"] = LocalCommand.run("/usr/bin/git", ["-C", cwd, "branch", "--show-current"], timeout: 1) ?? ""
            event["head"] = LocalCommand.run("/usr/bin/git", ["-C", cwd, "rev-parse", "HEAD"], timeout: 1) ?? ""
            event["files"] = LocalCommand.run("/usr/bin/git", ["-C", cwd, "status", "--porcelain", "--untracked-files=no"], timeout: 1) ?? ""
        }
        let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        let url = directory.appendingPathComponent((event["id"] as! String) + ".json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        DistributedNotificationCenter.default().postNotificationName(notification, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
