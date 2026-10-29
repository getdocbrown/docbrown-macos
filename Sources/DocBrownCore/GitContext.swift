import Foundation
import Darwin

public enum LocalCommand {
    /// File-backed output avoids pipe deadlocks for repositories with large histories.
    public static func run(_ executable: String, _ arguments: [String], directory: String? = nil, timeout: TimeInterval = 8) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_PAGER"] = "cat"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        guard let handle = try? FileHandle(forWritingTo: output) else { return nil }
        defer { try? handle.close(); try? FileManager.default.removeItem(at: output) }
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: output), data.count < 32_000_000 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct RepositoryContext: Sendable {
    public var root: String
    public var remote: String
}

public enum GitContext {
    public static func resolve(_ cwd: String) -> RepositoryContext? {
        guard !cwd.isEmpty, let root = LocalCommand.run("/usr/bin/git", ["-C", cwd, "rev-parse", "--show-toplevel"]), !root.isEmpty else { return nil }
        return RepositoryContext(root: root, remote: LocalCommand.run("/usr/bin/git", ["-C", cwd, "remote", "get-url", "origin"]) ?? "")
    }
    public static func githubSlug(_ remote: String) -> String? {
        let pattern = #"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: remote, range: NSRange(remote.startIndex..., in: remote)), let range = Range(m.range(at: 1), in: remote) else { return nil }
        return String(remote[range])
    }
    public static var ghPath: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

public actor AttributionService {
    private let store: HistoryStore
    private let gh: String?
    private let run: @Sendable (String, [String], TimeInterval) -> String?
    public init(store: HistoryStore, gh: String? = GitContext.ghPath, run: @escaping @Sendable (String, [String], TimeInterval) -> String? = { LocalCommand.run($0, $1, timeout: $2) }) {
        self.store = store; self.gh = gh; self.run = run
    }

    /// Sends repository identities to GitHub through the user's existing gh login, never transcript contents.
    public func refresh() throws -> String {
        guard let gh else { return "Install GitHub CLI (gh) to discover pull requests. Transcript links and git evidence still work locally." }
        guard run(gh, ["auth", "status"], 10) != nil else { return "GitHub CLI is not signed in. Run gh auth login, then refresh GitHub relationships." }
        let sessions = try store.rows("SELECT * FROM sessions WHERE remote<>'' AND source_kind<>'internal'")
        let grouped = Dictionary(grouping: sessions, by: { GitContext.githubSlug($0["remote"] ?? "") ?? "" })
        var linked = 0
        var failures = 0
        for (slug, group) in grouped where !slug.isEmpty {
            try Task.checkCancellation()
            guard let text = run(gh, ["pr", "list", "--repo", slug, "--state", "all", "--limit", "500", "--json", "number,title,url,headRefName,mergeCommit"], 25), let data = text.data(using: .utf8), let prs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { failures += 1; continue }
            for pr in prs {
                let branch = pr["headRefName"] as? String ?? ""
                let url = pr["url"] as? String ?? ""
                let number = pr["number"] as? Int ?? 0
                let candidates = group.filter { $0["branch"] == branch && !branch.isEmpty && !["main", "master", "develop"].contains(branch) }
                let allCandidates = candidates
                guard !allCandidates.isEmpty else { continue }
                let commitText = run(gh, ["pr", "view", String(number), "--repo", slug, "--json", "commits"], 15) ?? "{}"
                let commits = ((try? JSONSerialization.jsonObject(with: Data(commitText.utf8))) as? [String: Any])?["commits"] as? [[String: Any]] ?? []
                let hashes = Set(commits.compactMap { $0["oid"] as? String })
                for row in allCandidates {
                    let id = row["id"]!
                    let created = try store.associations(id).filter { $0.kind == "commit" && $0.confidence == "Confirmed" && hashes.contains($0.value) }
                    let confidence = created.isEmpty ? "Inferred" : "Confirmed"
                    let evidence = created.isEmpty ? "Transcript branch '\(branch)' matches PR #\(number). Branch reuse, rebases, and manual changes mean contribution is inferred." : "Git commit output in this transcript identifies \(created.map { String($0.value.prefix(12)) }.joined(separator: ", ")); GitHub lists the commit in this PR."
                    try store.addAssociation(sessionID: id, kind: "pr", value: url, title: pr["title"] as? String ?? "PR #\(number)", confidence: confidence, evidence: evidence, url: url)
                    linked += 1
                }
            }
            // Commit-to-PR lookup also finds renamed/deleted branches and PRs opened after a session.
            for row in group {
                let sessionID = row["id"]!
                for commit in try store.associations(sessionID).filter({ $0.kind == "commit" && $0.confidence == "Confirmed" }) {
                    guard let text = run(gh, ["api", "repos/\(slug)/commits/\(commit.value)/pulls"], 15),
                          let data = text.data(using: .utf8), let matches = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
                    for pr in matches {
                        guard let url = pr["html_url"] as? String else { continue }
                        try store.addAssociation(sessionID: sessionID, kind: "pr", value: url, title: pr["title"] as? String ?? url, confidence: "Confirmed", evidence: "Git commit output in this transcript reports \(commit.value.prefix(12)); GitHub confirms that commit belongs to this PR.", url: url)
                        linked += 1
                    }
                }
            }
        }
        return "Refreshed \(grouped.keys.filter { !$0.isEmpty }.count) repositories; \(linked) session relationships.\(failures > 0 ? " \(failures) repositories could not be read." : "")"
    }
}
