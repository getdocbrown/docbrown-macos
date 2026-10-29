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
                .navigationSplitViewColumnWidth(min: 205, ideal: 230, max: 280)
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
                    ContentUnavailableView(emptyTitle, systemImage: model.query.isEmpty ? "tray" : "magnifyingglass", description: Text(emptyDescription))
                    if model.query.isEmpty && model.repository.isEmpty && model.selectedPR == nil { Button("Import a Folder…") { model.addFolder() }.padding(.bottom, 30) }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.visibleSessions) { session in
                                Button { model.select(session.id) } label: { SessionRow(session: session, selected: model.selectedID == session.id).contentShape(Rectangle()) }
                                    .buttonStyle(.plain)
                            }
                            if model.canLoadMoreSessions { Button("Load more conversations") { model.reload(loadMore: true) }.buttonStyle(.plain).foregroundStyle(Design.cyan).padding() }
                        }.padding(.horizontal, 12).padding(.vertical, 5)
                    }.focusable().onMoveCommand { direction in
                        let list = model.visibleSessions
                        guard !list.isEmpty else { return }
                        let current = list.firstIndex { $0.id == model.selectedID } ?? -1
                        if direction == .down { model.select(list[min(list.count - 1, current + 1)].id) }
                        if direction == .up { model.select(list[max(0, current - 1)].id) }
                    }.accessibilityIdentifier("conversation-list")
                }
                Divider()
                HStack(spacing: 7) {
                    if model.importing { ProgressView().controlSize(.mini) }
                    else { Circle().fill(.green).frame(width: 5, height: 5) }
                    Text(model.status).lineLimit(2).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.padding(12)
            }
            .background(Design.panel)
            .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 420)
        } detail: {
            if let session = model.selectedSession {
                ConversationView(session: session)
            } else if let url = model.selectedPR, let pr = model.uniquePRs.first(where: { $0.url == url }) {
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

    private var emptyTitle: String {
        if !model.query.isEmpty { return "No conversations found" }
        if model.selectedPR != nil { return "No linked conversations yet" }
        return model.repository.isEmpty ? "Your history starts here" : "No conversations in this project yet"
    }
    private var emptyDescription: String {
        if !model.query.isEmpty { return "Try fewer words, a file path, or a different filter." }
        if model.selectedPR != nil { return "This PR is part of your GitHub activity. A matching local conversation hasn’t been found yet." }
        return model.repository.isEmpty ? "DocBrown automatically discovers local Codex and Claude Code transcripts. You can also import a folder." : "Conversations saved in this project’s folders appear here automatically."
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark().frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DocBrown").font(.system(size: 20, weight: .bold, design: .rounded)).tracking(-0.5)
                    Text("A MEMORY FOR YOUR WORK").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(0.8).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 17).padding(.top, 24).padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Library").padding(.horizontal, 10)
                        navRow("All conversations", icon: "square.stack", selected: model.selectedPR == nil && model.repository.isEmpty, count: model.sessionCount) {
                            model.selectedPR = nil; model.agent = ""; model.repository = ""; model.query = ""
                        }
                        HStack(spacing: 3) {
                            ForEach(["", "Codex", "Claude Code"], id: \.self) { agent in
                                Button(agent.isEmpty ? "All" : agent == "Claude Code" ? "Claude" : agent) { model.agent = agent }
                                    .font(.system(size: 10, weight: .medium)).buttonStyle(.plain).frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(model.agent == agent ? Design.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(model.agent == agent ? .primary : .secondary)
                            }
                        }.padding(3).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 8)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Projects").padding(.horizontal, 10).padding(.bottom, 5)
                        ForEach(model.projects) { project in
                            navRow(project.name, icon: "folder", selected: model.repository == project.id) { model.repository = project.id; model.selectedPR = nil }
                                .help(project.roots.joined(separator: "\n"))
                        }
                        if model.repositories.isEmpty { Text("Projects appear as history is imported.").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 10) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Eyebrow(text: "Pull requests"); Spacer(); Text(model.filteredPullRequests.count.formatted()).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary) }.padding(.horizontal, 10).padding(.bottom, 5)
                        prFilters
                        Text("Recently updated").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.horizontal, 10)
                        ForEach(Array(model.filteredPullRequests.prefix(7))) { pr in prRow(pr) }
                        if model.filteredPullRequests.count > 7 {
                            DisclosureGroup {
                                LazyVStack(spacing: 6) { ForEach(Array(model.filteredPullRequests.dropFirst(7))) { pr in prRow(pr) } }
                            } label: { Text("Show more").font(.system(size: 11)).foregroundStyle(.secondary) }.padding(.horizontal, 10).padding(.top, 7).tint(.secondary)
                        }
                        if model.filteredPullRequests.isEmpty {
                            Text(model.refreshingGitHub ? "Checking your GitHub activity…" : "No PRs in this view. Change filters or refresh GitHub activity.")
                                .font(.caption).foregroundStyle(.secondary).padding(10)
                        }
                    }
                }.padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) { Circle().fill(Design.cyan).frame(width: 5, height: 5); Text("Everything stays on this Mac").font(.system(size: 10)).foregroundStyle(.secondary) }
                HStack { Text(model.messageCount.formatted() + " memories").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary); Spacer(); KeyboardCap(text: "⌘D") }
            }.padding(20)
        }.background(.ultraThinMaterial)
    }
    private func navRow(_ title: String, icon: String, selected: Bool, count: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(selected ? Design.amber : Design.muted).frame(width: 16)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                if let count { Text(count.formatted()).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 10).padding(.vertical, 9).background(selected ? Design.amber.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var prFilters: some View {
        VStack(alignment: .leading, spacing: 5) {
        Menu {
            Picker("Show", selection: $model.prIncludeReferences) {
                Text("Your work").tag(false)
                Text("All activity, including mentions").tag(true)
            }
            Divider()
            Picker("Organization", selection: $model.prOrganization) {
                Text("All organizations").tag("")
                ForEach(model.prOrganizations, id: \.self) { Text($0).tag($0) }
            }
            Picker("Repository", selection: $model.prRepository) {
                Text("All repositories").tag("")
                ForEach(model.prRepositories, id: \.self) { Text($0).tag($0) }
            }
            if !model.prOrganization.isEmpty || !model.prRepository.isEmpty {
                Button("Clear organization and repository") { model.prOrganization = ""; model.prRepository = "" }
            }
            Divider()
            Button("Refresh GitHub activity") { model.refreshGitHub() }.disabled(model.refreshingGitHub)
        } label: {
            Label(model.prIncludeReferences ? "All activity" : "Your work", systemImage: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .medium))
        }.menuStyle(.borderlessButton)
            .help("Your work includes PRs you created, contributed commits to, reviewed, or commented on. Filter by organization or repository.")
        HStack(spacing: 4) {
            Text(!model.prRepository.isEmpty ? model.prRepository : model.prOrganization.isEmpty ? "All organizations & repositories" : model.prOrganization)
                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            if !model.prOrganization.isEmpty || !model.prRepository.isEmpty {
                Button { model.prOrganization = ""; model.prRepository = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                    .buttonStyle(.plain).help("Show all organizations and repositories")
            }
        }
        }.padding(.horizontal, 10).padding(.bottom, 4)
    }
    private func prRow(_ pr: PullRequestSummary) -> some View {
        Button { model.selectedPR = pr.url; model.query = ""; model.repository = ""; model.agent = "" } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.pull").foregroundStyle(pr.isInvolved ? Design.cyan : Design.muted)
                    Text(pr.repository).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text("#\(pr.number)").monospacedDigit().fixedSize()
                }.font(.system(size: 10, weight: .medium))
                Text(pr.title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                HStack {
                    Text(pr.involvement.first ?? "Mentioned").lineLimit(1)
                    Spacer(minLength: 3)
                    Text(DateText.display(pr.updated)).lineLimit(1)
                }.font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(model.selectedPR == pr.url ? Design.amber.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(pr.involvement.joined(separator: " · ") + "\n" + (pr.hasGitHubDate ? "Last PR update: " : "Last conversation: ") + pr.updated + "\n" + pr.url)
    }
}

struct SessionRow: View {
    let session: Session
    var selected = false
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                AgentBadge(agent: session.agent)
                Spacer()
                Text(DateText.display(session.updated)).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Text(session.title.isEmpty ? "Untitled conversation" : Design.readable(session.title)).font(.system(size: 13, weight: .medium)).lineSpacing(3).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            if !session.snippet.isEmpty { Text(session.snippet.replacingOccurrences(of: "\\n", with: " ")).font(.system(size: 11)).lineSpacing(3).lineLimit(2).foregroundStyle(.secondary) }
            HStack(spacing: 5) {
                Image(systemName: "folder").font(.system(size: 9))
                Text(session.projectName.isEmpty ? "No project" : session.projectName).lineLimit(1)
                Spacer(minLength: 5)
                Text(session.messageCount.formatted()).monospacedDigit()
                Image(systemName: "text.bubble").font(.system(size: 9))
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(15)
        .background(selected ? Design.raised : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Design.amber.opacity(0.3) : Design.line.opacity(0.4), lineWidth: 1))
        .overlay(alignment: .leading) { if selected { Capsule().fill(Design.amber).frame(width: 3, height: 28).offset(x: -1) } }
        .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 8, y: 4)
    }
}

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Design.canvas
                RadialGradient(colors: [Design.amber.opacity(0.075), .clear], center: .init(x: 0.8, y: 0.2), startRadius: 1, endRadius: 500)
                VStack(alignment: .leading, spacing: 23) {
                    HStack { Eyebrow(text: "Your work, remembered", color: Design.amber); Spacer(); BrandMark().frame(width: 140, height: 140) }.padding(.bottom, -20)
                    Text("Good ideas\ndon’t get lost.").font(.system(size: geometry.size.width < 500 ? 38 : 50, weight: .semibold, design: .rounded)).tracking(-2).lineSpacing(-1)
                    Text("Every prompt. Every decision. The story behind what you built — ready when you need it.").font(.system(size: 16)).foregroundStyle(.secondary).lineSpacing(6).frame(maxWidth: 365)
                    HStack(spacing: 12) {
                        Button { model.showSearch() } label: { HStack(spacing: 22) { Text("Find something").fontWeight(.medium); KeyboardCap(text: "⌘D") }.padding(.horizontal, 6).padding(.vertical, 4) }.buttonStyle(.borderedProminent).tint(Design.amber).foregroundStyle(.black)
                        Button("Import a folder…") { model.addFolder() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.top, 4)
                    Text("Codex and Claude Code history is imported automatically. No setup required.").font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(Design.line).frame(height: 1).padding(.top, 26)
                    HStack(spacing: 35) {
                        stat(model.sessionCount.formatted(), "Conversations")
                        stat(model.repositories.count.formatted(), "Projects")
                        stat(model.messageCount.formatted(), "Messages")
                    }
                    Label("Private by design. No cloud required.", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 10)
                }.frame(maxWidth: 510).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    func stat(_ number: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(number).font(.system(size: 27, weight: .medium, design: .rounded)).tracking(-0.5); Text(label).font(.system(size: 10)).foregroundStyle(.secondary) }
    }
}
