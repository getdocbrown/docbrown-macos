import SwiftUI
#if canImport(DocBrownCore)
import DocBrownCore
#endif

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 205, ideal: 235, max: 300)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search history, files, commits, PRs…", text: $model.query)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .accessibilityIdentifier("history-search")
                    if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }
                .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10)).padding(14)
                HStack {
                    Text(model.selectedPR == nil ? "CONVERSATIONS" : "PR TIMELINE").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.4)
                    Spacer()
                    Text("\(model.visibleSessions.count)").font(.caption.monospacedDigit())
                }.foregroundStyle(.secondary).padding(.horizontal, 18).padding(.bottom, 8)
                if model.visibleSessions.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "Your history starts here" : "No conversations found", systemImage: model.query.isEmpty ? "tray" : "magnifyingglass", description: Text(model.query.isEmpty ? "DocBrown automatically discovers local Codex and Claude Code transcripts. You can also import a folder." : "Try fewer words, a file path, or a different filter."))
                    if model.query.isEmpty { Button("Import a Folder…") { model.addFolder() }.padding(.bottom, 30) }
                } else {
                    List(selection: $model.selectedID) {
                        ForEach(model.visibleSessions) { session in
                            SessionRow(session: session).tag(session.id)
                        }
                        if model.canLoadMoreSessions { Button("Load more conversations") { model.reload(loadMore: true) }.buttonStyle(.plain).foregroundStyle(.tint) }
                    }.listStyle(.inset).accessibilityIdentifier("conversation-list")
                }
                Divider()
                HStack(spacing: 7) {
                    if model.importing { ProgressView().controlSize(.mini) }
                    else { Circle().fill(.green).frame(width: 5, height: 5) }
                    Text(model.status).lineLimit(2).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.padding(12)
            }
            .navigationSplitViewColumnWidth(min: 290, ideal: 350, max: 460)
        } detail: {
            if let session = model.selectedSession {
                ConversationView(session: session)
            } else if let url = model.selectedPR, let pr = model.uniquePRs.first(where: { $0.value == url }) {
                PRDetail(pr: pr)
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { searchFocused = true } label: { Label("Search History", systemImage: "magnifyingglass") }.keyboardShortcut("f", modifiers: .command)
            }
            ToolbarItem {
                Button { model.scan() } label: { Label("Scan for New Conversations", systemImage: "arrow.clockwise") }.disabled(model.importing)
            }
            ToolbarItem { SettingsLink { Label("Settings", systemImage: "gearshape") } }
        }
        .onChange(of: model.query) { model.reload(debounce: true) }
        .onChange(of: model.agent) { model.reload() }
        .onChange(of: model.repository) { model.reload() }
        .onChange(of: model.selectedID) { model.select(model.selectedID) }
        .onChange(of: model.selectedPR) { model.selectedID = nil; model.reload() }
        .alert("DocBrown couldn’t complete that action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DocBrown").font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("THE HISTORY BEHIND YOUR CODE").font(.system(size: 7, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 26)
            List {
                Section("Library") {
                    Button { model.selectedPR = nil; model.agent = ""; model.repository = ""; model.query = "" } label: {
                        Label { HStack { Text("All conversations"); Spacer(); Text(model.sessionCount.formatted()).foregroundStyle(.secondary).font(.caption) } } icon: { Image(systemName: "bubble.left.and.bubble.right") }
                    }.buttonStyle(.plain).padding(.vertical, 4)
                    Picker("Agent", selection: $model.agent) {
                        Text("All agents").tag("")
                        Text("Codex").tag("Codex")
                        Text("Claude Code").tag("Claude Code")
                    }.labelsHidden()
                }
                Section("Repositories") {
                    Button { model.repository = "" } label: { Label("All repositories", systemImage: model.repository.isEmpty ? "folder.fill" : "folder") }.buttonStyle(.plain)
                    ForEach(model.repositories, id: \.self) { path in
                        Button { model.repository = path; model.selectedPR = nil } label: {
                            Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: model.repository == path ? "folder.fill" : "folder").lineLimit(1)
                        }.buttonStyle(.plain).help(path).foregroundStyle(model.repository == path ? Color.accentColor : .primary)
                    }
                }
                Section("Pull requests") {
                    if model.uniquePRs.isEmpty {
                        Text("PRs appear as relationships are discovered.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.uniquePRs) { pr in
                        Button { model.selectedPR = pr.value; model.query = ""; model.repository = ""; model.agent = "" } label: {
                            Label(prLabel(pr), systemImage: "arrow.triangle.pull").lineLimit(2)
                        }.buttonStyle(.plain).help(pr.value)
                    }
                }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 5) {
                Label("Local by design", systemImage: "lock.shield").font(.caption.weight(.medium))
                Text("\(model.messageCount.formatted()) messages · v0.1.0").font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }
    }
    private func prLabel(_ pr: Association) -> String {
        let parts = pr.value.split(separator: "/")
        return parts.count >= 5 ? "\(parts[parts.count-3]) #\(parts.last!)" : pr.title
    }
}

struct SessionRow: View {
    let session: Session
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(session.agent.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.7).foregroundStyle(session.agent == "Codex" ? Color.teal : Color.orange)
                Spacer()
                Text(DateText.display(session.updated)).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Text(session.title.isEmpty ? "Untitled conversation" : session.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            if !session.snippet.isEmpty { Text(session.snippet).font(.caption).lineLimit(3).foregroundStyle(.secondary) }
            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 9))
                Text(session.projectName.isEmpty ? "No repository" : session.projectName).lineLimit(1)
                Spacer(minLength: 5)
                Text("\(session.messageCount.formatted()) msgs")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.vertical, 9)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            BrandMark().frame(width: 210, height: 210).padding(.leading, -30).padding(.bottom, -30)
            Text("Pick up where\nyou left off.").font(.system(size: 43, weight: .semibold, design: .rounded)).tracking(-1.5)
            Text("The prompts, decisions, and conversations behind your work. Together in one searchable place.").font(.system(size: 16)).foregroundStyle(.secondary).lineSpacing(5).frame(maxWidth: 410, alignment: .leading)
            HStack(spacing: 28) {
                stat(model.sessionCount.formatted(), "CONVERSATIONS")
                stat(model.repositories.count.formatted(), "REPOSITORIES")
                stat(model.uniquePRs.count.formatted(), "PULL REQUESTS")
            }.padding(.vertical, 10)
            Divider().frame(maxWidth: 410)
            Label("Search with ⌘F. Select a conversation to explore.", systemImage: "magnifyingglass").font(.callout).foregroundStyle(.secondary)
            Label("Your history stays on this Mac.", systemImage: "lock.shield").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
    func stat(_ number: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(number).font(.system(size: 27, weight: .medium, design: .rounded)); Text(label).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(.secondary) }
    }
}
