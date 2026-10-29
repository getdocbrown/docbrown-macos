import Foundation

public struct HistoryProject: Identifiable, Sendable {
    public var id: String { roots[0] }
    public var name: String
    public var roots: [String]
}

public enum ProjectCatalog {
    /// Reads project names and folders only. Codex owns this file; never modify it.
    public static func codexProjects(home: URL = FileManager.default.homeDirectoryForCurrentUser, stateFile: URL? = nil) -> [HistoryProject] {
        let directory = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: stateFile ?? directory.appendingPathComponent(".codex-global-state.json")),
              let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let projects = state["local-projects"] as? [String: [String: Any]] else { return [] }
        let order = state["project-order"] as? [String] ?? []
        return projects.keys.sorted {
            let left = order.firstIndex(of: $0) ?? Int.max
            let right = order.firstIndex(of: $1) ?? Int.max
            return left == right ? $0 < $1 : left < right
        }.compactMap { id in
            guard let project = projects[id] else { return nil }
            var seen = Set<String>()
            let roots = (project["rootPaths"] as? [String] ?? []).filter { $0.hasPrefix("/") }
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }.filter { seen.insert($0).inserted }
            guard let first = roots.first else { return nil }
            let name = (project["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return HistoryProject(name: name.isEmpty ? URL(fileURLWithPath: first).lastPathComponent : name, roots: roots)
        }
    }

    public static func merged(discovered: [String], configured: [HistoryProject], excluded: [String] = []) -> [HistoryProject] {
        func contains(_ root: String, _ path: String) -> Bool { path == root || path.hasPrefix(root == "/" ? "/" : root + "/") }
        func allowed(_ path: String) -> Bool { !excluded.contains { contains($0, path) } }
        var seen = Set<String>()
        var result = configured.compactMap { project -> HistoryProject? in
            let roots = project.roots.filter(allowed)
            guard let first = roots.first, seen.insert(first).inserted else { return nil }
            return HistoryProject(name: project.name, roots: roots)
        }
        for path in discovered where !path.isEmpty && allowed(path) {
            guard !result.contains(where: { $0.roots.contains { contains($0, path) } }), seen.insert(path).inserted else { continue }
            result.append(HistoryProject(name: URL(fileURLWithPath: path).lastPathComponent, roots: [path]))
        }
        return result
    }
}
