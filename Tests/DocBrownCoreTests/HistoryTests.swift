import XCTest
@testable import DocBrownCore

final class HistoryTests: XCTestCase {
    var root: URL!
    var input: URL!
    var store: HistoryStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        input = root.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        store = try HistoryStore(paths: LibraryPaths(directory: root.appendingPathComponent("library")))
    }
    override func tearDownWithError() throws { store = nil; try? FileManager.default.removeItem(at: root) }
    func line(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]); data.append(10); return data
    }
    func writeCodex(_ name: String = "session.jsonl", message: String = "We chose Redis for caching") throws -> URL {
        let path = input.appendingPathComponent(name)
        var data = try line(["type":"session_meta", "timestamp":"2026-01-01T10:00:00Z", "payload":["id":"test-codex", "cwd":"/missing/repo", "git":["branch":"feature/cache", "commit_hash":"abc123", "repository_url":"https://github.com/example/repo.git"]]])
        data.append(try line(["type":"turn_context", "payload":["model":"test-model"]]))
        data.append(try line(["type":"event_msg", "payload":["type":"user_message","message":message]]))
        data.append(try line(["type":"response_item", "timestamp":"2026-01-01T10:00:01Z", "payload":["type":"message","role":"user","content":[["type":"input_text","text":message]]]]))
        data.append(try line(["type":"response_item", "timestamp":"2026-01-01T10:00:02Z", "payload":["type":"message","role":"assistant","content":[["type":"output_text","text":"See src/cache.swift and https://github.com/example/repo/pull/42"]]]]))
        try data.write(to: path); return path
    }
    func testCodexImportSearchAndIdempotency() async throws {
        let path = try writeCodex()
        let importer = TranscriptImporter(store: store)
        let first = await importer.scan(roots: [input])
        XCTAssertEqual(first.messages, 2); XCTAssertTrue(first.errors.isEmpty)
        let result = try store.search("Redis caching")
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result.first?.model, "test-model"); XCTAssertEqual(result.first?.branch, "feature/cache")
        XCTAssertEqual(try store.search("src/cache.swift").count, 1)
        XCTAssertEqual(try store.search("42").count, 1)
        XCTAssertEqual(try store.search("Redis", agent: "Claude Code").count, 0)
        let second = await importer.scan(roots: [input]); XCTAssertEqual(second.messages, 0)
        XCTAssertEqual(try store.counts().messages, 2)
        let archive = try XCTUnwrap(store.rows("SELECT raw_name FROM sources").first?["raw_name"])
        XCTAssertEqual(try Data(contentsOf: store.paths.raw.appendingPathComponent(archive)), try Data(contentsOf: path))
        XCTAssertEqual(try store.associations().first?.confidence, "Referenced")
    }
    func testNonGitProjectIsListedAndMatchesNestedHistory() throws {
        for (id, cwd, repo) in [("root", "/projects/new_app", ""), ("nested", "/projects/new_app/server", "/projects/new_app/server"), ("sibling", "/projects/new_app-other", ""), ("underscore", "/projects/newXapp", "")] {
            try store.execute("INSERT INTO sessions(id,agent,cwd,repository) VALUES(?,?,?,?)", [id,"Codex",cwd,repo])
            try store.execute("INSERT INTO messages VALUES(?,?,?,?,?,?,?,?,?)", [id+"-m",id,"user","Project history","","","","fixture",1])
        }
        XCTAssertTrue(try store.repositories().contains("/projects/new_app"))
        XCTAssertEqual(Set(try store.search(repository: "/projects/new_app").map(\.id)), ["root","nested"])
        XCTAssertEqual(Set(try store.search("history", repository: "/projects/new_app", projectRoots: ["/projects/new_app","/projects/new_app-other"]).map(\.id)), ["root","nested","sibling"])
    }

    func testCodexProjectCatalogIncludesEmptyProjectsNamesAndMultipleRoots() throws {
        let file = root.appendingPathComponent("codex-state.json")
        let state: [String: Any] = ["local-projects":[
            "new":["name":"New project","rootPaths":["/projects/new","/projects/shared"]],
            "existing":["name":"Existing project","rootPaths":["/projects/existing"]],
            "invalid":["name":"Remote","rootPaths":["ssh://somewhere"]]
        ],"project-order":["new","existing"]]
        let bytes = try JSONSerialization.data(withJSONObject: state)
        try bytes.write(to: file)
        let configured = ProjectCatalog.codexProjects(stateFile: file)
        XCTAssertEqual(configured.map(\.name), ["New project","Existing project"])
        XCTAssertEqual(configured.first?.roots, ["/projects/new","/projects/shared"])
        let merged = ProjectCatalog.merged(discovered: ["/projects/new/subrepo","/projects/cli","/projects/shared"], configured: configured)
        XCTAssertEqual(merged.map(\.id), ["/projects/new","/projects/existing","/projects/cli"])
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(ProjectCatalog.merged(discovered: [], configured: configured, excluded: ["/projects/new","/projects/shared"]).map(\.name), ["Existing project"])
        try Data("{unfinished".utf8).write(to: file)
        XCTAssertTrue(ProjectCatalog.codexProjects(stateFile: file).isEmpty)
    }
    func testQuickSearchRanksRelevantConversationsAboveRecentIncidentalMentions() throws {
        func insert(_ id: String, title: String, body: String, updated: String) throws {
            try store.execute("INSERT INTO sessions(id,agent,title,updated) VALUES(?,?,?,?)", [id, "Codex", title, updated])
            try store.execute("INSERT INTO messages VALUES(?,?,?,?,?,?,?,?,?)", [id + "-message", id, "user", body, updated, "", "", "fixture", 1])
        }
        try insert("recent", title: "Weekly notes", body: "cache " + String(repeating: "unrelated discussion ", count: 250), updated: "2026-10-29")
        try insert("focused", title: "Storage decisions", body: "cache configuration and cache eviction", updated: "2026-10-20")
        try insert("title", title: "Cache", body: "Implementation details", updated: "2026-10-01")
        try insert("unrelated", title: "Window layout", body: "Sidebar appearance", updated: "2026-10-30")

        let matches = try store.search("cache", rankByRelevance: true)
        XCTAssertEqual(matches.map(\.id), ["title", "focused", "recent"])
        XCTAssertTrue(matches[1].snippet.contains("cache"))
        XCTAssertEqual(try store.search("cache", limit: 1, offset: 1, rankByRelevance: true).first?.id, "focused")
        XCTAssertEqual(try store.search("cache", agent: "Claude Code", rankByRelevance: true).count, 0)
        XCTAssertEqual(try store.search("nothing matches", rankByRelevance: true).count, 0)
        XCTAssertEqual(try store.search(rankByRelevance: true).first?.id, "unrelated")
        XCTAssertEqual(try store.search("cache").first?.id, "recent")
        XCTAssertNoThrow(try store.search("OR NOT * : \"", rankByRelevance: true))
    }
    func testIncrementalPartialLineAndRestart() async throws {
        let path = try writeCodex()
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        let extra = try line(["type":"response_item", "timestamp":"2026-01-01T10:00:03Z", "payload":["type":"message","role":"assistant","content":[["type":"output_text","text":"Incremental message"]]]])
        let h = try FileHandle(forWritingTo: path); try h.seekToEnd(); try h.write(contentsOf: extra.dropLast(3)); try h.close()
        _ = await TranscriptImporter(store: store).scan(roots: [input]); XCTAssertEqual(try store.counts().messages, 2)
        let h2 = try FileHandle(forWritingTo: path); try h2.seekToEnd(); try h2.write(contentsOf: extra.suffix(3)); try h2.close()
        _ = await TranscriptImporter(store: store).scan(roots: [input]); XCTAssertEqual(try store.counts().messages, 3)
        XCTAssertEqual(try store.search("Incremental").count, 1)
    }
    func testCanceledImportResumesWithoutLosingOrDuplicatingMessages() async throws {
        let path = try writeCodex()
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        for index in 0..<2000 {
            try handle.write(contentsOf: line(["type":"response_item","payload":["type":"message","role":"assistant","content":[["text":"Import checkpoint \(index)"]]]]))
        }
        try handle.close()
        let importer = TranscriptImporter(store: store)
        let running = Task { await importer.scan(roots: [input]) }
        try await Task.sleep(for: .milliseconds(10))
        running.cancel()
        _ = await running.value
        _ = await importer.scan(roots: [input])
        XCTAssertEqual(try store.counts().messages, 2002)
        XCTAssertEqual(try store.rows("PRAGMA integrity_check").first?["integrity_check"], "ok")
        let archive = try XCTUnwrap(store.rows("SELECT raw_name FROM sources").first?["raw_name"])
        XCTAssertEqual(try Data(contentsOf: store.paths.raw.appendingPathComponent(archive)), try Data(contentsOf: path))
    }
    func testClaudeBlocksAndModels() async throws {
        let path = input.appendingPathComponent("claude.jsonl")
        var data = try line(["type":"user","sessionId":"claude-1","uuid":"u1","cwd":"/missing/project","gitBranch":"fix","timestamp":"2026-01-02T10:00:00Z","message":["role":"user","content":"Fix authentication"]])
        data.append(try line(["type":"assistant","sessionId":"claude-1","uuid":"a1","timestamp":"2026-01-02T10:00:01Z","message":["model":"claude-test","content":[["type":"text","text":"Updating authentication"],["type":"tool_use","name":"Edit","input":["file_path":"auth.swift"]]]]]))
        data.append(try line(["type":"user","sessionId":"claude-1","uuid":"u2","timestamp":"2026-01-02T10:00:02Z","message":["content":[["type":"tool_result","content":"Done"]]]]))
        try data.write(to: path)
        let report = await TranscriptImporter(store: store).scan(roots: [input])
        XCTAssertTrue(report.errors.isEmpty); XCTAssertEqual(report.messages, 4)
        let session = try XCTUnwrap(store.search("auth.swift").first)
        XCTAssertEqual(session.agent, "Claude Code"); XCTAssertEqual(session.model, "claude-test")
        let messages = try store.messages(session.id); XCTAssertEqual(messages.filter { $0.role == "tool" }.count, 2)
        XCTAssertEqual(messages[1].body, "Updating authentication")
    }
    func testMalformedUnknownAndDeletionTombstone() async throws {
        let path = try writeCodex()
        let handle = try FileHandle(forWritingTo: path); try handle.seekToEnd(); try handle.write(contentsOf: Data("{broken}\n{\"type\":\"future_record\"}\n".utf8)); try handle.close()
        let importer = TranscriptImporter(store: store)
        let report = await importer.scan(roots: [input]); XCTAssertEqual(report.errors.count, 1)
        let id = try XCTUnwrap(store.search().first?.id)
        try store.deleteSession(id)
        _ = await importer.scan(roots: [input]); XCTAssertEqual(try store.counts().messages, 0); XCTAssertEqual(try store.counts().sessions, 0)
    }
    func testMovedTranscriptDoesNotDuplicate() async throws {
        let path = try writeCodex()
        let importer = TranscriptImporter(store: store)
        _ = await importer.scan(roots: [input])
        try FileManager.default.copyItem(at: path, to: input.appendingPathComponent("archive-copy.jsonl"))
        _ = await importer.scan(roots: [input]); XCTAssertEqual(try store.counts().messages, 2)
    }
    func testExclusionAndSearchPunctuation() async throws {
        _ = try writeCodex(message: "A quoted \"phrase\", src/a_b.swift 100% safe")
        let importer = TranscriptImporter(store: store)
        _ = await importer.scan(roots: [input], excluded: ["/missing/repo"])
        XCTAssertEqual(try store.counts().messages, 0)
        _ = await importer.scan(roots: [input])
        XCTAssertEqual(try store.search("\"phrase\"").count, 1)
        XCTAssertEqual(try store.search("src/a_b.swift").count, 1)
        XCTAssertEqual(try store.search("100%").count, 1)
        XCTAssertNoThrow(try store.search("OR NOT * : \""))
        XCTAssertEqual(try store.search("zzzz%").count, 0)
    }
    func testStrongerEvidenceIsNotOverwritten() throws {
        try store.execute("INSERT INTO sessions(id,agent) VALUES('s','Codex')")
        try store.addAssociation(sessionID: "s", kind: "pr", value: "42", title: "PR", confidence: "Confirmed", evidence: "Commit membership")
        try store.addAssociation(sessionID: "s", kind: "pr", value: "42", title: "PR", confidence: "Referenced", evidence: "Mention")
        XCTAssertEqual(try store.associations().first?.confidence, "Confirmed")
    }
    func testSearchJumpsToMatchingContext() async throws {
        let path = try writeCodex()
        let h = try FileHandle(forWritingTo: path); try h.seekToEnd()
        for i in 0..<300 { try h.write(contentsOf: line(["type":"response_item","timestamp":String(format:"2026-01-01T11:%02d:%02dZ",i/60,i%60),"payload":["type":"message","role":"assistant","content":[["text":i == 280 ? "rare-needle" : "filler"]]]])) }
        try h.close()
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        let id = try XCTUnwrap(store.search("rare-needle").first?.id)
        XCTAssertEqual(try store.firstMatchOffset(id, query: "rare-needle"), 282)
        XCTAssertTrue(try store.messages(id, offset: 279).contains { $0.body == "rare-needle" })
    }
    func testGitHubRemoteParsing() {
        XCTAssertEqual(GitContext.githubSlug("git@github.com:example/repo.git"), "example/repo")
        XCTAssertEqual(GitContext.githubSlug("https://github.com/example/repo.git"), "example/repo")
        XCTAssertNil(GitContext.githubSlug("https://github.com.evil.test/example/repo.git"))
    }
    func testInternalReviewSessionsAreOptional() async throws {
        let path = try writeCodex()
        var text = try String(contentsOf: path)
        text = text.replacingOccurrences(of: "\"id\":\"test-codex\"", with: "\"id\":\"test-codex\",\"thread_source\":\"guardian_review\"")
        try text.write(to: path, atomically: true, encoding: .utf8)
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        XCTAssertEqual(try store.search().count, 0)
        XCTAssertEqual(try store.search(includeInternal: true).count, 1)
        XCTAssertEqual(try store.counts().messages, 0)
        XCTAssertEqual(try store.counts(includeInternal: true).messages, 2)
    }
    func testClaudeIncrementalInCustomFolderAndNoFinalNewline() async throws {
        let path = input.appendingPathComponent("custom.jsonl")
        let first = try line(["type":"user","sessionId":"c","uuid":"one","message":["content":"First"]])
        try first.dropLast().write(to: path)
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        XCTAssertEqual(try store.counts().messages, 1)
        let h = try FileHandle(forWritingTo: path); try h.seekToEnd()
        try h.write(contentsOf: Data("\n".utf8))
        try h.write(contentsOf: line(["type":"assistant","sessionId":"c","uuid":"two","message":["model":"claude","content":"Second"]]))
        try h.close()
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        XCTAssertEqual(try store.counts().messages, 2)
        XCTAssertEqual(try store.search("Second").first?.agent, "Claude Code")
    }
    func testPRAttributionAfterBranchRename() async throws {
        try store.execute("INSERT INTO sessions(id,agent,remote,branch) VALUES('s','Codex','https://github.com/example/repo.git','old-name')")
        try store.addAssociation(sessionID: "s", kind: "commit", value: String(repeating: "a", count: 40), title: "commit", confidence: "Confirmed", evidence: "Git output")
        let service = AttributionService(store: store, gh: "/test/gh") { _, args, _ in
            if args.first == "auth" { return "signed in" }
            if args.first == "pr" { return "[]" }
            return "[{\"html_url\":\"https://github.com/example/repo/pull/27\",\"title\":\"Renamed feature\"}]"
        }
        _ = try await service.refresh()
        XCTAssertEqual(try store.associations().first?.confidence, "Confirmed")
        XCTAssertEqual(try store.associations().first?.title, "Renamed feature")
    }
    func testBranchOnlyPRAttributionIsInferred() async throws {
        try store.execute("INSERT INTO sessions(id,agent,remote,branch) VALUES('s','Codex','https://github.com/example/repo.git','feature')")
        let service = AttributionService(store: store, gh: "/test/gh") { _, args, _ in
            if args.first == "auth" { return "signed in" }
            if args.contains("list") { return "[{\"number\":27,\"url\":\"https://github.com/example/repo/pull/27\",\"headRefName\":\"feature\",\"title\":\"Feature\"}]" }
            return "{\"commits\":[]}"
        }
        _ = try await service.refresh()
        XCTAssertEqual(try store.associations().first?.confidence, "Inferred")
    }

    func testPRSidebarFiltersParticipationAndSortsByActivity() throws {
        func add(_ number: Int, repo: String = "team/app", date: String, confidence: String = "Referenced", author: String = "other", reviewed: Bool = false, commented: Bool = false) throws {
            let id = "session-\(number)"
            let url = "https://github.com/\(repo)/pull/\(number)"
            try store.execute("INSERT INTO sessions(id,agent,updated) VALUES(?,?,?)", [id,"Codex",date])
            try store.addAssociation(sessionID: id, kind: "pr", value: url, title: "PR \(number)", confidence: confidence, evidence: "fixture", url: url)
            if confidence != "Confirmed" {
                try store.recordPullRequest(["url":url,"title":"Change \(number)","author":["login":author],"updatedAt":date], viewer: "me", reviewed: reviewed, commented: commented)
            }
        }
        try add(99, date: "2026-10-01T00:00:00Z", author: "me")
        try add(1, date: "2026-10-12T00:00:00Z", author: "me")
        try add(2, date: "2026-10-10T00:00:00Z", confidence: "Confirmed")
        try add(3, date: "2026-10-11T00:00:00Z", commented: true)
        try add(5, repo: "another/tools", date: "2026-10-15T00:00:00Z", reviewed: true)
        try add(900, date: "2026-10-29T00:00:00Z")
        try add(88, date: "2026-10-30T00:00:00Z", confidence: "Inferred")
        let items = try store.pullRequestSummaries()
        XCTAssertEqual(PullRequestSummary.filtered(items, includeReferences: false).map(\.number), [5,1,3,2,99])
        XCTAssertEqual(PullRequestSummary.filtered(items, includeReferences: true).map(\.number), [88,900,5,1,3,2,99])
        XCTAssertEqual(PullRequestSummary.filtered(items, includeReferences: false, organization: "another").map(\.number), [5])
        XCTAssertEqual(PullRequestSummary.filtered(items, includeReferences: false, repository: "team/app").map(\.number), [1,3,2,99])
        XCTAssertFalse(try XCTUnwrap(items.first { $0.number == 2 }).hasGitHubDate)
        XCTAssertEqual(try XCTUnwrap(items.first { $0.number == 88 }).involvement, ["Branch match"])
        XCTAssertEqual(try XCTUnwrap(items.first { $0.number == 900 }).involvement, ["Mentioned"])
    }

    func testPRMetadataKeepsCachedParticipationOfflineAndResetsForAnotherAccount() throws {
        let url = "https://github.com/team/app/pull/1"
        try store.recordPullRequest(["url":url,"author":["login":"me"],"title":"Feature"], viewer: "me", reviewed: true)
        try store.recordPullRequest(["html_url":url,"title":"Updated feature"], viewer: "")
        var row = try XCTUnwrap(store.rows("SELECT * FROM pull_requests").first)
        XCTAssertEqual(row["authored"], "1"); XCTAssertEqual(row["reviewed"], "1")
        XCTAssertEqual(row["title"], "Updated feature")
        try store.recordPullRequest(["url":url,"author":["login":"me"]], viewer: "someone-else")
        row = try XCTUnwrap(store.rows("SELECT * FROM pull_requests").first)
        XCTAssertEqual(row["authored"], "0"); XCTAssertEqual(row["reviewed"], "0")
    }

    func testPRSummaryDeduplicatesAndDoesNotUseHiddenReviewEvidence() throws {
        let url = "https://github.com/team/app/pull/1"
        try store.execute("INSERT INTO sessions(id,agent,updated,source_kind) VALUES('user','Codex','2026-10-01','user'),('hidden','Codex','2026-10-29','internal')")
        try store.addAssociation(sessionID: "user", kind: "pr", value: url, title: "Mention", confidence: "Referenced", evidence: "Link")
        try store.addAssociation(sessionID: "hidden", kind: "pr", value: url, title: "Internal review", confidence: "Confirmed", evidence: "Hidden review")
        let visible = try store.pullRequestSummaries()
        XCTAssertEqual(visible.count, 1)
        XCTAssertFalse(try XCTUnwrap(visible.first).isInvolved)
        XCTAssertEqual(visible.first?.updated, "2026-10-01")
        let all = try store.pullRequestSummaries(includeInternal: true)
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(try XCTUnwrap(all.first).isInvolved)
        XCTAssertEqual(all.first?.updated, "2026-10-29")
    }

    func testGitHubParticipationUsesAuthorReviewsAndCommentsNotMentions() async throws {
        try store.execute("INSERT INTO sessions(id,agent,remote) VALUES('s','Codex','https://github.com/team/app.git')")
        for number in 1...4 {
            let url = "https://github.com/team/app/pull/\(number)"
            try store.addAssociation(sessionID: "s", kind: "pr", value: url, title: "PR \(number)", confidence: "Referenced", evidence: "Mention only", url: url)
        }
        let service = AttributionService(store: store, gh: "/test/gh") { _, args, _ in
            if args.first == "auth" { return "signed in" }
            if args.first == "api" && args.contains("user") { return "me" }
            let numbers: [Int] = args.contains("q=is:pr author:me") ? [1] : args.contains("q=is:pr reviewed-by:me") ? [2] : args.contains("q=is:pr commenter:me") ? [3] : [1,2,3,4]
            let prs: [[String: Any]] = numbers.map { ["number":$0,"url":"https://github.com/team/app/pull/\($0)","title":"Change \($0)","author":["login":$0 == 1 ? "me" : "other"],"updatedAt":"2026-10-29T00:00:00Z"] }
            return String(data: try! JSONSerialization.data(withJSONObject: prs), encoding: .utf8)
        }
        _ = try await service.refresh()
        let items = try store.pullRequestSummaries()
        XCTAssertEqual(Set(PullRequestSummary.filtered(items, includeReferences: false).map(\.number)), [1,2,3])
        XCTAssertFalse(try XCTUnwrap(items.first { $0.number == 4 }).isInvolved)
        XCTAssertTrue(try store.associations().allSatisfy { $0.confidence == "Referenced" })
    }

    func testRecentAccountActivityAppearsWithoutRepositoryOrConversationLinks() async throws {
        try store.recordPullRequest(["url":"https://github.com/other/account/pull/1","author":["login":"previous-account"]], viewer: "previous-account")
        let service = AttributionService(store: store, gh: "/test/gh") { _, args, _ in
            if args.first == "auth" { return "signed in" }
            if args.first == "api" && args.contains("user") { return "me" }
            if args.contains("q=is:pr author:me") {
                return "[{\"url\":\"https://github.com/team/main-app/pull/500\",\"title\":\"Latest work\",\"author\":{\"login\":\"me\"},\"updatedAt\":\"2026-10-29T11:00:00Z\"}]"
            }
            return "[]"
        }
        _ = try await service.refresh()
        try store.recordPullRequest(["url":"https://github.com/team/older/pull/2","author":["login":"me"],"updatedAt":"2026-10-14T12:00:00Z"], viewer: "me")
        let items = PullRequestSummary.filtered(try store.pullRequestSummaries(), includeReferences: false, organization: "team")
        XCTAssertEqual(items.map(\.number), [500,2])
        XCTAssertFalse(try store.pullRequestSummaries().contains { $0.repository == "other/account" })
        XCTAssertEqual(try store.associations().count, 0)
        XCTAssertEqual(try store.counts().sessions, 0)
        XCTAssertEqual(PullRequestSummary.filtered(items, includeReferences: false, repository: "team/main-app").count, 1)
    }

    func testPRActivityKeepsNewestPageWhenLaterPageFails() async throws {
        let service = AttributionService(store: store, gh: "/test/gh") { _, args, _ in
            if args.first == "auth" { return "signed in" }
            if args.contains("user") { return "me" }
            if args.contains("q=is:pr author:me") {
                if args.contains("page=2") { return nil }
                let prs: [[String: Any]] = (1...100).map { ["url":"https://github.com/team/app/pull/\($0)","author":["login":"me"],"updatedAt":"2026-10-29T12:00:00Z"] }
                return String(data: try! JSONSerialization.data(withJSONObject: prs), encoding: .utf8)
            }
            return "[]"
        }
        let status = try await service.refresh()
        XCTAssertTrue(status.contains("1 GitHub lookups"))
        XCTAssertEqual(try store.pullRequestSummaries().count, 100)
    }

    func testHookInstallPreservesSettingsAndUninstallsOnlyOwnedCommands() throws {
        let config = root.appendingPathComponent("settings.json")
        let initial: [String: Any] = ["model":"chosen-model", "hooks":["PostToolUse":[["matcher":"Bash","hooks":[["type":"command","command":"echo existing"]]]]]]
        try JSONSerialization.data(withJSONObject: initial).write(to: config)
        let helper = root.appendingPathComponent("helper")
        try Data("test helper".utf8).write(to: helper)
        let installer = HookInstaller(paths: store.paths)
        try installer.install(.claude, bundledHelper: helper, config: config)
        try installer.install(.claude, bundledHelper: helper, config: config)
        var output = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        XCTAssertEqual(output["model"] as? String, "chosen-model")
        let hooks = output["hooks"] as! [String: [[String: Any]]]
        XCTAssertEqual(hooks["PostToolUse"]?.count, 2)
        XCTAssertTrue(installer.status(.claude, config: config).hasPrefix("Configured"))
        try installer.uninstall(.claude, config: config)
        output = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
        let remaining = output["hooks"] as! [String: [[String: Any]]]
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining["PostToolUse"]?.count, 1)
        XCTAssertEqual(output["model"] as? String, "chosen-model")
        XCTAssertFalse((try FileManager.default.contentsOfDirectory(atPath: store.paths.directory.appendingPathComponent("Backups").path)).isEmpty)
    }
    func testInvalidHookConfigIsNeverOverwritten() throws {
        let config = root.appendingPathComponent("hooks.json")
        let bytes = Data("{bad-json".utf8); try bytes.write(to: config)
        let installer = HookInstaller(paths: store.paths)
        XCTAssertThrowsError(try installer.install(.codex, bundledHelper: root.appendingPathComponent("missing"), config: config))
        XCTAssertEqual(try Data(contentsOf: config), bytes)
        XCTAssertEqual(HookInstaller.shellQuote("a'b"), "'a'\\''b'")
    }
    func testHookGitSnapshotAndIngestion() async throws {
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        XCTAssertNotNil(LocalCommand.run("/usr/bin/git", ["init", repo.path]))
        let path = try writeCodex()
        var text = try String(contentsOf: path)
        text = text.replacingOccurrences(of: "/missing/repo", with: repo.path)
        try text.write(to: path, atomically: true, encoding: .utf8)
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        let payload: [String: Any] = ["session_id":"test-codex", "cwd":repo.path, "hook_event_name":"SessionStart"]
        try HookCapture.capture(provider: .codex, input: JSONSerialization.data(withJSONObject: payload), paths: store.paths)
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        XCTAssertEqual(try store.rows("SELECT * FROM git_observations").count, 1)
        _ = await TranscriptImporter(store: store).scan(roots: [input])
        XCTAssertEqual(try store.rows("SELECT * FROM git_observations").count, 1)
        try store.deleteSession("Codex:test-codex")
        XCTAssertEqual(try store.rows("SELECT * FROM git_observations").count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.paths.directory.appendingPathComponent("HookEvents").path).count, 0)
        try HookCapture.capture(provider: .codex, input: JSONSerialization.data(withJSONObject: payload), paths: store.paths)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.paths.directory.appendingPathComponent("HookEvents").path).count, 0)
    }
    func testHookCaptureHonorsRepositoryExclusions() throws {
        try CapturePolicy.saveExclusions(["/excluded"], paths: store.paths)
        XCTAssertFalse(CapturePolicy.permits(sessionID: "Codex:s", cwd: "/excluded/project", paths: store.paths))
        XCTAssertTrue(CapturePolicy.permits(sessionID: "Codex:s", cwd: "/excluded-other", paths: store.paths))
    }

    func testCommitCommandMustBeAnInvocation() {
        XCTAssertTrue(TranscriptImporter.isCommitCommand("git add . && git commit -m 'fix'"))
        XCTAssertTrue(TranscriptImporter.isCommitCommand("{\"cmd\":\"git -C /tmp/repo commit -m fix\"}"))
        XCTAssertFalse(TranscriptImporter.isCommitCommand("echo git commit"))
        XCTAssertFalse(TranscriptImporter.isCommitCommand("git log --oneline"))
    }
    func testAttachmentMetadataDoesNotBecomeTheTitle() {
        XCTAssertNil(TranscriptParser.displayTitle("<environment_context>metadata</environment_context>"))
        XCTAssertNil(TranscriptParser.displayTitle("# Files mentioned by the user:\nAttachment"))
        XCTAssertEqual(TranscriptParser.displayTitle("# Files pasted by the user:\nAttachment\n## My request:\nBuild the app"), "Build the app")
    }

    func testReadingViewSeparatesKnownContextWithoutChangingThePrompt() {
        let original = "<environment_context>private paths</environment_context>\n\nPlease improve **readability**."
        let reading = ReadingText(original)
        XCTAssertEqual(reading.body, "Please improve **readability**.")
        XCTAssertTrue(reading.context.contains("private paths"))
        XCTAssertEqual(ReadingText("Explain <example>XML</example>").body, "Explain <example>XML</example>")
        XCTAssertTrue(ReadingText("<external_codex_apps_open_page>{}</external_codex_apps_open_page>").isContextOnly)
    }
    func testMarkdownBlocksPreserveCodeAndStructure() {
        let blocks = MarkdownBlock.parse("## Approach\n\nA **clear** explanation.\n\n- First\n- Second\n\n```swift\nlet x = 1\n```\n\n> Remember this")
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks[0].kind, .heading(2))
        XCTAssertEqual(blocks[4].kind, .code("swift"))
        XCTAssertEqual(blocks[4].text, "let x = 1")
        XCTAssertEqual(blocks[5].kind, .quote)
        XCTAssertEqual(MarkdownBlock.parse("| A | B |\n|---|---|\n|1|2|").first?.kind, .table([["A", "B"], ["1", "2"]]))
    }
    func testToolPresentationUnwrapsNestedOutput() {
        XCTAssertEqual(ToolReading.text("{\"output\":\"Build succeeded\\n19 tests passed\"}"), "Build succeeded\n19 tests passed")
        XCTAssertEqual(ToolReading.text("{\"cmd\":\"swift test\"}"), "swift test")
    }

}
