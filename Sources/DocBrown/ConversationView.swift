import SwiftUI
#if canImport(DocBrownCore)
import DocBrownCore
#endif

struct ConversationView: View {
    @EnvironmentObject var model: AppModel
    let session: Session
    @State private var inspectContext = false
    @State private var showReferences = false
    private var items: [ReadingItem] { ReadingItem.build(model.messages) }
    private var references: [Association] { model.relationships.filter { $0.confidence == "Referenced" } }
    private var evidence: [Association] { model.relationships.filter { $0.confidence != "Referenced" } }
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Design.line).frame(height: 1)
            HStack(spacing: 12) {
                Eyebrow(text: "Conversation")
                Text(session.messageCount.formatted() + " records").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Toggle("Activity", isOn: $model.showTools).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11)).help("Show grouped tool activity between messages")
            }.padding(.horizontal, 32).padding(.vertical, 14)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if model.messageOffset > 0 {
                            Button { model.earlierMessages() } label: { Label("Load earlier conversation", systemImage: "arrow.up") }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 8)
                        }
                        ForEach(items) { item in
                            switch item.kind {
                            case .message:
                                if let message = item.messages.first { MessageView(message: message, search: model.query).id(item.id) }
                            case .context: ContextRow(messages: item.messages).id(item.id)
                            case .activity:
                                if model.showTools { ActivityRow(messages: item.messages).id(item.id) }
                            }
                        }
                        if model.canLoadMore {
                            Button { model.moreMessages() } label: { Label("Continue reading", systemImage: "arrow.down") }.buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity).padding(16)
                        }
                        if model.messages.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(60) }
                    }
                    .frame(maxWidth: 790, alignment: .leading)
                    .padding(.horizontal, 36).padding(.top, 14).padding(.bottom, 60)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: session.id) { _, _ in if let first = items.first { proxy.scrollTo(first.id, anchor: .top) } }
            }
        }.background(Design.canvas)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                AgentBadge(agent: session.agent)
                Text("/").foregroundStyle(.quaternary)
                Text(session.projectName.isEmpty ? "Your library" : session.projectName).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(DateText.display(session.started)).font(.system(size: 11)).foregroundStyle(.tertiary)
                Menu {
                    Button("Export Conversation…") { model.exportSelected() }
                    Button("Show Library in Finder") { NSWorkspace.shared.open(model.paths.directory) }
                    Divider()
                    Button("Remove from Library…", role: .destructive) { model.deleteSelected() }
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }.menuStyle(.borderlessButton).fixedSize()
            }
            Text(session.title.isEmpty ? "Untitled conversation" : String(Design.readable(session.title).prefix(110)) + (Design.readable(session.title).count > 110 ? "…" : ""))
                .font(.system(size: 22, weight: .semibold, design: .rounded)).tracking(-0.5).lineSpacing(3).lineLimit(2).textSelection(.enabled).help(session.title)
            HStack(spacing: 16) {
                if !session.model.isEmpty { Label(session.model, systemImage: "sparkle").lineLimit(1) }
                if !session.branch.isEmpty { Label(session.branch, systemImage: "arrow.triangle.branch").lineLimit(1) }
                Spacer()
                if !references.isEmpty { Button { showReferences.toggle() } label: { Label("\(references.count) references", systemImage: "link") }.buttonStyle(.plain).help("PRs mentioned in the conversation; mentions do not establish contribution") }
                Button { inspectContext.toggle() } label: { Label("Details", systemImage: "sidebar.right") }.buttonStyle(.plain)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            if inspectContext {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Directory   \(session.cwd)")
                    Text("Repository  \(session.repository.isEmpty ? "Not recorded" : session.repository)")
                    Text("HEAD        \(session.head.isEmpty ? "Not recorded" : session.head)")
                    Text("Session     \(session.id)")
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Design.canvas, in: RoundedRectangle(cornerRadius: 10))
            }
            if !evidence.isEmpty || showReferences {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(evidence + (showReferences ? references : [])) { item in
                            Button {
                                if item.kind == "pr" { model.selectedPR = item.value }
                                else { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.value, forType: .string) }
                            } label: {
                                Label(item.kind == "pr" ? "#\(item.value.split(separator: "/").last ?? "") · \(item.confidence)" : "\(item.title) · \(item.confidence)", systemImage: item.kind == "pr" ? "arrow.triangle.pull" : "point.3.connected.trianglepath.dotted")
                                    .font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6).background(Design.raised, in: Capsule())
                            }.buttonStyle(.plain).foregroundStyle(.secondary).help(item.evidence)
                        }
                    }
                }
            }
        }.padding(.horizontal, 32).padding(.top, 25).padding(.bottom, 22).background(Design.panel)
    }
}

struct MessageView: View {
    let message: Message
    let search: String
    @State private var showOriginal = false
    @State private var full = false
    @State private var hover = false
    private var reading: ReadingText { ReadingText(message.body, extractContext: message.role == "user") }
    private var isUser: Bool { message.role == "user" }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill((isUser ? Design.amber : Design.cyan).opacity(0.12)).frame(width: 28, height: 28)
                    Image(systemName: isUser ? "person.fill" : "sparkle").font(.system(size: 12, weight: .medium)).foregroundStyle(isUser ? Design.amber : Design.cyan)
                }
                Text(isUser ? "You" : "Assistant").font(.system(size: 12, weight: .semibold))
                if !isUser && !message.model.isEmpty { Text(message.model).font(.system(size: 10)).foregroundStyle(.tertiary) }
                Spacer()
                Text(DateText.display(message.timestamp, withTime: true)).font(.system(size: 10)).foregroundStyle(.tertiary)
                Menu {
                    Button("Copy original message") { copy(message.body) }
                    Button(showOriginal ? "Show reading view" : "Inspect original message") { showOriginal.toggle() }
                } label: { Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 20, height: 20) }.menuStyle(.borderlessButton).fixedSize().opacity(hover ? 1 : 0.35)
            }
            Group {
                if showOriginal { CodeBlock(text: full ? message.body : String(message.body.prefix(18000)), language: "Original source · line \(message.sourceLine)") }
                else { MarkdownView(text: full ? reading.body : String(reading.body.prefix(18000))) }
            }
            .padding(isUser ? 20 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isUser ? Design.raised : .clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay { if isUser { RoundedRectangle(cornerRadius: 14).stroke(Design.line) } }
            if !reading.context.isEmpty && !showOriginal {
                DisclosureGroup { CodeBlock(text: reading.context, language: "Message context") } label: { Label("Attached context", systemImage: "paperclip").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            if !full && message.body.count > 18000 { Button("Read the complete message") { full = true }.font(.caption).buttonStyle(.plain).foregroundStyle(Design.cyan) }
        }.onHover { hover = $0 }
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

struct ContextRow: View {
    let messages: [Message]
    var body: some View {
        DisclosureGroup {
            ForEach(messages) { message in CodeBlock(text: message.body, language: "Source context") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tray.full").foregroundStyle(.tertiary)
                Text("Session context").foregroundStyle(.secondary)
                Text("Environment & instructions").foregroundStyle(.tertiary)
            }.font(.system(size: 11))
        }.tint(.secondary).padding(.horizontal, 14).padding(.vertical, 12).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ActivityRow: View {
    let messages: [Message]
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "terminal").foregroundStyle(Design.cyan.opacity(0.65))
                    Text("\(messages.count) tool events").foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.quaternary)
                    Text("View activity").foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }.font(.system(size: 11)).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                ForEach(messages) { message in ToolEventView(message: message) }
            }
        }.padding(.horizontal, 14).padding(.vertical, 12).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }
}
struct ToolEventView: View {
    let message: Message
    @State private var full = false
    var body: some View {
        DisclosureGroup {
            CodeBlock(text: full ? ToolReading.text(message.body) : String(ToolReading.text(message.body).prefix(24000)), language: message.tool)
            HStack {
                if !full && message.body.count > 24000 { Button("Show complete output") { full = true } }
                Spacer()
                Button("Copy original record") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.body, forType: .string) }
            }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(message.tool).font(.system(size: 10, weight: .semibold)).foregroundStyle(Design.cyan)
                Text(ToolReading.summary(message)).font(.system(size: 11, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
            }
        }.tint(.secondary)
    }
}
struct PRDetail: View {
    @EnvironmentObject var model: AppModel
    let pr: PullRequestSummary
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("PULL REQUEST", systemImage: "arrow.triangle.pull").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
                Text(pr.title).font(.largeTitle.weight(.semibold))
                if let url = URL(string: pr.url) { Link(pr.url, destination: url).font(.caption) }
                Text(pr.involvement.joined(separator: " · ")).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Text("The conversations behind this change").font(.title3)
                Text("References and inferred relationships are labeled individually. A mention or matching branch alone does not prove contribution.").font(.callout).foregroundStyle(.secondary)
                ForEach(model.visibleSessions.sorted { $0.started < $1.started }) { session in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(DateText.display(session.started)).font(.caption.monospaced()); Spacer(); Text(session.agent).font(.caption).foregroundStyle(.secondary) }
                        Button(session.title.isEmpty ? "Untitled conversation" : session.title) { model.select(session.id) }.font(.headline).buttonStyle(.plain).foregroundStyle(.tint)
                        ForEach(model.pullRequests.filter { $0.sessionID == session.id && $0.value == pr.url }) { relation in
                            Label(relation.confidence, systemImage: relation.confidence == "Confirmed" ? "checkmark.seal" : "info.circle").font(.caption.weight(.semibold))
                            Text(relation.evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(36).frame(maxWidth: 850)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
