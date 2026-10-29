import SwiftUI
#if canImport(DocBrownCore)
import DocBrownCore
#endif

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    private var controller: AppController?
    private var hookObserver: NSObjectProtocol?
    private var pendingHookScan: Task<Void, Never>?
    @Published var hookStatuses: [String: String] = [:]
    @Published var hookMessage = ""
    func openSetup() { controller?.openSetup() }
    func refreshHookStatuses() {
        let installer = HookInstaller(paths: paths)
        for provider in HookProvider.allCases { hookStatuses[provider.rawValue] = installer.status(provider) }
    }
    func configureHooks(_ provider: HookProvider, install: Bool) {
        do {
            let installer = HookInstaller(paths: paths)
            if install {
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/docbrown")
                guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw DatabaseError(message: "Install hooks from the packaged DocBrown.app, which includes the capture helper.") }
                try installer.install(provider, bundledHelper: helper)
                hookMessage = "Installed for \(provider.name). Review and allow the DocBrown commands in your agent’s hooks settings, then start a new session."
            } else {
                try installer.uninstall(provider)
                hookMessage = "Removed DocBrown’s hooks for \(provider.name). Your other settings and hooks were preserved."
            }
            refreshHookStatuses()
        } catch { hookMessage = error.localizedDescription }
    }
    private var quickSearchTask: Task<Void, Never>?
    @Published var quickQuery = ""
    @Published var quickResults: [Session] = []
    @Published var quickSelection = 0
    @Published var quickSearching = false
    @Published var quickFocusToken = UUID()
    @Published var hotkeyError = ""
    @Published var hotkeyChoice = UserDefaults.standard.string(forKey: "hotkey") ?? "command-d" {
        didSet { UserDefaults.standard.set(hotkeyChoice, forKey: "hotkey"); controller?.registerShortcut() }
    }
    var hotkeyLabel: String {
        switch hotkeyChoice {
        case "command-d": return "⌘D"
        case "control-option-command-d": return "⌃⌥⌘D"
        case "control-option-d": return "⌃⌥D"
        case "control-shift-d": return "⌃⇧D"
        default: return "⌃⌥Space"
        }
    }
    func showSearch() { controller?.showSearch() }
    func hideSearch() { controller?.hideSearch() }
    func openLibrary(sessionID: String? = nil) { controller?.openLibrary(sessionID: sessionID) }
    func openQuickSelection() {
        guard quickResults.indices.contains(quickSelection) else { return }
        openLibrary(sessionID: quickResults[quickSelection].id)
    }
    func searchQuickly() {
        quickSearchTask?.cancel()
        guard let reader else { return }
        let text = quickQuery, includeInternal = includeInternal
        quickSearching = true
        quickSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            do {
                let results = try await Task.detached(priority: .userInitiated) { try reader.search(text, limit: 30, includeInternal: includeInternal) }.value
                guard !Task.isCancelled else { return }
                quickResults = results; quickSelection = 0; quickSearching = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; quickSearching = false } }
        }
    }
    func openConversation(_ id: String) {
        guard let reader else { return }
        query = quickQuery; agent = ""; repository = ""; selectedPR = nil
        if !sessions.contains(where: { $0.id == id }), let session = try? reader.session(id) { sessions.insert(session, at: 0) }
        select(id)
        reload()
    }

    @Published var sessions: [Session] = []
    @Published var repositories: [String] = []
    @Published var pullRequests: [Association] = []
    @Published var query = ""
    @Published var agent = ""
    @Published var repository = ""
    @Published var selectedID: String?
    @Published var messages: [Message] = []
    @Published var relationships: [Association] = []
    @Published var status = "Opening your local history…"
    @Published var error: String?
    @Published var importing = false
    @Published var refreshingGitHub = false
    @Published var sessionCount = 0
    @Published var messageCount = 0
    @Published var messageOffset = 0
    @Published var canLoadMore = false
    @Published var canLoadMoreSessions = false
    @Published var showTools = true
    @Published var selectedPR: String?
    @Published var importErrors: [String] = []
    @Published var githubStatus = ""
    @Published var lastImport: Date?
    @Published var automatic = UserDefaults.standard.object(forKey: "automatic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automatic, forKey: "automatic") }
    }
    @Published var includeInternal = UserDefaults.standard.bool(forKey: "includeInternal") {
        didSet { UserDefaults.standard.set(includeInternal, forKey: "includeInternal"); reload() }
    }
    @Published var excludedText = (UserDefaults.standard.stringArray(forKey: "excluded") ?? []).joined(separator: "\n")
    @Published var customRoots = UserDefaults.standard.stringArray(forKey: "customRoots") ?? []
    let paths: LibraryPaths
    private var reader: HistoryStore?
    private var importer: TranscriptImporter?
    private var attribution: AttributionService?
    private var searchTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var didRefreshGitHub = false
    private var lastGitHubRefresh = Date.distantPast

    init() {
        if let path = ProcessInfo.processInfo.environment["DOCBROWN_LIBRARY"] { paths = LibraryPaths(directory: URL(fileURLWithPath: path)) }
        else { paths = LibraryPaths() }
        do {
            reader = try HistoryStore(paths: paths)
            importer = try TranscriptImporter(store: HistoryStore(paths: paths))
            attribution = try AttributionService(store: HistoryStore(paths: paths))
        } catch { self.error = error.localizedDescription; status = "Could not open library" }
    }
    var selectedSession: Session? { sessions.first { $0.id == selectedID } }
    var excluded: [String] { excludedText.split(whereSeparator: \.isNewline).map { NSString(string: String($0).trimmingCharacters(in: .whitespaces)).expandingTildeInPath }.filter { !$0.isEmpty } }
    var roots: [URL] { LibraryPaths.defaultRoots + customRoots.map { URL(fileURLWithPath: $0) } }
    var visibleSessions: [Session] {
        guard let selectedPR else { return sessions }
        let ids = Set(pullRequests.filter { $0.value == selectedPR }.map(\.sessionID))
        return sessions.filter { ids.contains($0.id) }
    }
    var uniquePRs: [Association] {
        var seen = Set<String>()
        return pullRequests.filter { seen.insert($0.value).inserted }
    }

    func start() {
        guard watchTask == nil else { return }
        controller = AppController(model: self)
        hookObserver = DistributedNotificationCenter.default().addObserver(forName: HookCapture.notification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.automatic else { return }
                self.pendingHookScan?.cancel()
                self.pendingHookScan = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    if !Task.isCancelled { self.scan() }
                }
            }
        }
        refreshHookStatuses()
        reload()
        scan()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                if self.automatic { self.scan(); if Date().timeIntervalSince(self.lastGitHubRefresh) > 600 { self.refreshGitHub() } }
            }
        }
    }
    func reload(debounce: Bool = false, loadMore: Bool = false) {
        searchTask?.cancel()
        let query = query, agent = agent, repository = repository, includeInternal = includeInternal
        let limit = loadMore ? sessions.count + 200 : max(200, selectedPR == nil ? 200 : 10000)
        guard let reader else { return }
        searchTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    (try reader.search(query, agent: agent, repository: repository, limit: limit, includeInternal: includeInternal), try reader.repositories(), try reader.associations(includeInternal: includeInternal), try reader.counts(includeInternal: includeInternal))
                }.value
                guard !Task.isCancelled else { return }
                sessions = result.0; repositories = result.1; pullRequests = result.2
                sessionCount = result.3.sessions; messageCount = result.3.messages
                canLoadMoreSessions = sessions.count == limit
            } catch { self.error = error.localizedDescription }
        }
    }
    func select(_ id: String?) {
        selectedID = id; messages = []; relationships = []; canLoadMore = false; messageOffset = 0
        guard let id, let reader else { return }
        detailTask?.cancel()
        detailTask = Task {
            do {
                let query = query
                let result = try await Task.detached(priority: .userInitiated) {
                    let offset = max(0, (try reader.firstMatchOffset(id, query: query) ?? 0) - 3)
                    return (try reader.messages(id, offset: offset), try reader.associations(id), offset)
                }.value
                guard !Task.isCancelled, selectedID == id else { return }
                messages = result.0; relationships = result.1; messageOffset = result.2; canLoadMore = messages.count == 250
            } catch { self.error = error.localizedDescription }
        }
    }
    func earlierMessages() {
        guard let id = selectedID, let reader else { return }
        let offset = max(0, messageOffset - 250)
        let count = messageOffset - offset
        Task {
            do {
                let result = try await Task.detached { try reader.messages(id, limit: count, offset: offset) }.value
                guard selectedID == id else { return }
                messages = result + messages; messageOffset = offset
            } catch { self.error = error.localizedDescription }
        }
    }
    private func refreshSelection() {
        guard let id = selectedID, let reader else { return }
        let offset = messageOffset, limit = max(250, messages.count)
        Task {
            do {
                let result = try await Task.detached { (try reader.messages(id, limit: limit, offset: offset), try reader.associations(id)) }.value
                guard selectedID == id else { return }
                messages = result.0; relationships = result.1; canLoadMore = result.0.count == limit
            } catch { self.error = error.localizedDescription }
        }
    }
    func moreMessages() {
        guard let id = selectedID, let reader else { return }
        let offset = messageOffset + messages.count
        Task {
            do {
                let result = try await Task.detached { try reader.messages(id, offset: offset) }.value
                guard selectedID == id else { return }
                messages += result; canLoadMore = result.count == 250
            } catch { self.error = error.localizedDescription }
        }
    }
    func scan() {
        guard !importing, let importer else { return }
        importing = true; status = "Looking for conversations…"
        let roots = roots, excluded = excluded
        importTask = Task {
            let report = await importer.scan(roots: roots, excluded: excluded) { [weak self] report in
                if report.files % 10 == 0 {
                    Task { @MainActor in
                        self?.status = "Indexed \(report.files) transcripts · \(report.messages.formatted()) new messages"
                        if report.files % 40 == 0 { self?.reload() }
                    }
                }
            }
            importing = false; lastImport = Date(); importErrors = report.errors
            status = report.errors.isEmpty ? "Up to date · everything stays on this Mac" : "Import completed with \(report.errors.count) issues"
            reload()
            if report.messages > 0 { refreshSelection() }
            if !didRefreshGitHub { didRefreshGitHub = true; refreshGitHub() }
        }
    }
    func refreshGitHub() {
        guard !refreshingGitHub, let attribution else { return }
        refreshingGitHub = true; lastGitHubRefresh = Date(); githubStatus = "Finding pull request relationships…"
        Task {
            do { githubStatus = try await attribution.refresh(); reload(); refreshSelection() }
            catch { githubStatus = error.localizedDescription }
            refreshingGitHub = false
        }
    }
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.message = "Choose a folder containing Codex or Claude Code JSONL transcripts. Originals are never modified."
        if panel.runModal() == .OK {
            customRoots = Array(Set(customRoots + panel.urls.map(\.path))).sorted()
            UserDefaults.standard.set(customRoots, forKey: "customRoots"); scan()
        }
    }
    func saveExclusions() {
        UserDefaults.standard.set(excluded, forKey: "excluded")
        status = "Exclusions saved. Existing history can be removed from each conversation."
    }
    func deleteSelected() {
        guard let id = selectedID, let reader else { return }
        let alert = NSAlert()
        alert.messageText = "Remove this conversation from DocBrown?"
        alert.informativeText = "Its local archive and searchable messages will be removed. The original agent transcript is untouched. Automatic import will skip this source in the future."
        alert.addButton(withTitle: "Remove conversation"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                // Serialize deletion behind any in-progress import using the importer's actor.
                if let importTask { await importTask.value }
                try reader.deleteSession(id); select(nil); reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    func exportSelected() {
        guard let id = selectedID, let reader else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "DocBrown-conversation.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let text = try await Task.detached {
                    let session = try reader.session(id)
                    let messages = try reader.messages(id, limit: Int(Int32.max))
                    return "# \(session?.title ?? "Conversation")\n\nAgent: \(session?.agent ?? "")\nRepository: \(session?.repository ?? "")\nBranch: \(session?.branch ?? "")\n\n" + messages.map { "## \($0.role.capitalized) · \($0.timestamp)\n\n\($0.body)" }.joined(separator: "\n\n---\n\n")
                }.value
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch { self.error = error.localizedDescription }
        }
    }
}
