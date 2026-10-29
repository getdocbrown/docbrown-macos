import Foundation
import DocBrownCore

@main struct DocBrownCLI {
    static func main() async {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            var directory: URL?
            if let index = args.firstIndex(of: "--library"), index + 1 < args.count {
                directory = URL(fileURLWithPath: args[index + 1]); args.removeSubrange(index...index + 1)
            }
            if args.first == "hook", args.count > 1, let provider = HookProvider(rawValue: args[1]) {
                let input = FileHandle.standardInput.readDataToEndOfFile()
                try? HookCapture.capture(provider: provider, input: input, paths: LibraryPaths(directory: directory))
                return
            }
            let store = try HistoryStore(paths: LibraryPaths(directory: directory))
            let command = args.first ?? "help"
            let value = args.dropFirst().joined(separator: " ")
            switch command {
            case "import":
                let roots = args.count > 1 ? args.dropFirst().map { URL(fileURLWithPath: $0) } : LibraryPaths.defaultRoots
                let report = await TranscriptImporter(store: store).scan(roots: roots)
                try emit(["files": report.files, "newMessages": report.messages, "errors": report.errors])
                if !report.errors.isEmpty { exit(2) }
            case "stats":
                let counts = try store.counts()
                try emit(["sessions": counts.sessions, "messages": counts.messages, "repositories": try store.repositories().count])
            case "search", "file", "pr":
                try emit(try store.search(value, limit: 1000).map { ["id": $0.id, "title": $0.title, "agent": $0.agent, "repository": $0.repository, "branch": $0.branch, "model": $0.model, "updated": $0.updated, "snippet": $0.snippet] })
            case "session":
                try emit(try store.messages(value, limit: Int(Int32.max)).map { ["role": $0.role, "body": $0.body, "timestamp": $0.timestamp, "model": $0.model, "tool": $0.tool, "source": $0.sourcePath, "line": String($0.sourceLine)] })
            case "github": try emit(["status": try await AttributionService(store: store).refresh()])
            default:
                print("""
                DocBrown 0.1.2 — the history behind your code
                Usage: docbrown [--library PATH] COMMAND [ARGUMENT]
                  import [FOLDER...]  Import or incrementally update local history
                  search WORDS        Search messages and context
                  file PATH           Find conversations mentioning a file
                  pr URL_OR_NUMBER    Find conversations related to a pull request
                  session ID          Print original messages as JSON
                  stats               Show library counts
                  github              Refresh GitHub relationships using gh
                """)
            }
        } catch {
            FileHandle.standardError.write(Data(("DocBrown: \(error.localizedDescription)\n").utf8)); exit(1)
        }
    }
    static func emit(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        FileHandle.standardOutput.write(data); print("")
    }
}
