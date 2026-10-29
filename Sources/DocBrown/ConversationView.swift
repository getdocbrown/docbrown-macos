import SwiftUI
#if canImport(DocBrownCore)
import DocBrownCore
#endif

struct ConversationView: View {
    @EnvironmentObject var model: AppModel
    let session: Session
    @State private var inspectContext = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(session.agent.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(.orange)
                    if !session.model.isEmpty { Text(session.model).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Menu {
                        Button("Export Conversation…") { model.exportSelected() }
                        Button("Show Library in Finder") { NSWorkspace.shared.open(model.paths.directory) }
                        Divider()
                        Button("Remove from Library…", role: .destructive) { model.deleteSelected() }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24)
                }
                Text(session.title.isEmpty ? "Untitled conversation" : session.title).font(.system(size: 23, weight: .semibold)).lineLimit(3).textSelection(.enabled)
                HStack(spacing: 14) {
                    Label(session.projectName.isEmpty ? "No repository recorded" : session.projectName, systemImage: "folder")
                    if !session.branch.isEmpty { Label(session.branch, systemImage: "arrow.triangle.branch").lineLimit(1) }
                    Spacer()
                    Button { inspectContext.toggle() } label: { Label("Context", systemImage: "info.circle") }.buttonStyle(.plain)
                }.font(.caption).foregroundStyle(.secondary)
                if inspectContext {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Working directory: \(session.cwd.isEmpty ? "Not recorded" : session.cwd)")
                        Text("Repository: \(session.repository.isEmpty ? "Unavailable locally" : session.repository)")
                        Text("Recorded branch: \(session.branch.isEmpty ? "Not recorded" : session.branch)")
                        Text("Recorded HEAD: \(session.head.isEmpty ? "Not recorded" : session.head)")
                        Text("Started: \(session.started) · Updated: \(session.updated)")
                        Text("Session: \(session.id)")
                        Text("Repository discovery reflects local state; branch and HEAD above come from transcripts or local capture hooks.").foregroundStyle(.secondary)
                    }.font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                if !model.relationships.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(model.relationships) { item in
                                Button {
                                    if item.kind == "pr" { model.selectedPR = item.value }
                                    else { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.value, forType: .string) }
                                } label: {
                                    HStack(spacing: 5) { Image(systemName: item.kind == "pr" ? "arrow.triangle.pull" : "point.3.connected.trianglepath.dotted"); Text(item.kind == "pr" ? "PR #\(item.value.split(separator: "/").last ?? "")" : item.title); Text("· \(item.confidence)").foregroundStyle(.secondary) }
                                        .font(.caption2).padding(.horizontal, 9).padding(.vertical, 5).background(.quaternary, in: Capsule())
                                }.buttonStyle(.plain).help(item.evidence)
                            }
                        }
                    }
                }
            }.padding(24)
            Divider()
            HStack {
                Text("TRANSCRIPT").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.3).foregroundStyle(.secondary)
                Text("\(session.messageCount.formatted()) messages").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Toggle("Tool activity", isOn: $model.showTools).toggleStyle(.checkbox).font(.caption)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.messageOffset > 0 { Button("Load earlier context") { model.earlierMessages() }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                        ForEach(model.messages.filter { model.showTools || $0.role != "tool" }) { message in
                            MessageView(message: message, search: model.query).id(message.id)
                        }
                        if model.canLoadMore {
                            Button("Load next 250 messages") { model.moreMessages() }.buttonStyle(.bordered).frame(maxWidth: .infinity).padding()
                        }
                        if model.messages.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }.onChange(of: session.id) { _, _ in if let first = model.messages.first { proxy.scrollTo(first.id, anchor: .top) } }
            }
        }.background(Color(nsColor: .textBackgroundColor))
    }
}

struct MessageView: View {
    let message: Message
    let search: String
    @State private var expanded = false
    @State private var full = false
    private var isTool: Bool { message.role == "tool" }
    private var visibleBody: String { full ? message.body : String(message.body.prefix(isTool ? 5000 : 18000)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isTool ? "terminal" : message.role == "user" ? "person.crop.circle" : "sparkle").foregroundStyle(isTool ? .secondary : message.role == "user" ? Color.orange : Color.teal)
                Text(isTool ? message.tool : message.role == "user" ? "You" : "Assistant").font(.system(size: 12, weight: .semibold))
                if !message.model.isEmpty && message.role == "assistant" { Text(message.model).font(.system(size: 10)).foregroundStyle(.tertiary) }
                Spacer()
                Text(time(message.timestamp)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                if isTool { Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse tool activity" : "Expand tool activity") }
            }
            if !isTool || expanded {
                Text(visibleBody).font(isTool ? .system(size: 11, design: .monospaced) : .system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if !full && message.body.count > (isTool ? 5000 : 18000) { Button("Show complete message (\(message.body.count.formatted()) characters)") { full = true }.font(.caption) }
                HStack {
                    Text("Source line \(message.sourceLine)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).help(message.sourcePath)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.body, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text(String(message.body.prefix(130)).replacingOccurrences(of: "\n", with: " ")).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(16)
        .background(isTool ? Color(nsColor: .controlBackgroundColor).opacity(0.7) : message.role == "user" ? Color.orange.opacity(0.055) : Color(nsColor: .controlBackgroundColor).opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
    }
    private func time(_ value: String) -> String {
        DateText.display(value, withTime: true)
    }
}

struct PRDetail: View {
    @EnvironmentObject var model: AppModel
    let pr: Association
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("PULL REQUEST", systemImage: "arrow.triangle.pull").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
                Text(pr.title).font(.largeTitle.weight(.semibold))
                if let url = URL(string: pr.url) { Link(pr.url, destination: url).font(.caption) }
                Text("The conversations behind this change").font(.title3)
                Text("References and inferred relationships are labeled individually. A mention or matching branch alone does not prove contribution.").font(.callout).foregroundStyle(.secondary)
                ForEach(model.visibleSessions.sorted { $0.started < $1.started }) { session in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(DateText.display(session.started)).font(.caption.monospaced()); Spacer(); Text(session.agent).font(.caption).foregroundStyle(.secondary) }
                        Button(session.title.isEmpty ? "Untitled conversation" : session.title) { model.select(session.id) }.font(.headline).buttonStyle(.plain).foregroundStyle(.tint)
                        ForEach(model.pullRequests.filter { $0.sessionID == session.id && $0.value == pr.value }) { relation in
                            Label(relation.confidence, systemImage: relation.confidence == "Confirmed" ? "checkmark.seal" : "info.circle").font(.caption.weight(.semibold))
                            Text(relation.evidence).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(36).frame(maxWidth: 850)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
