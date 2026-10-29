import SwiftUI

struct QuickSearchView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                BrandMark().frame(width: 46, height: 46)
                QuickSearchField(text: $model.quickQuery, focusToken: model.quickFocusToken)
                    .frame(height: 34)
                Text("esc").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }.padding(.horizontal, 24).padding(.top, 23).padding(.bottom, 21)
            Divider()
            HStack {
                Text(model.quickQuery.isEmpty ? "RECENT CONVERSATIONS" : "SEARCH RESULTS").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                Spacer()
                if model.quickSearching { ProgressView().controlSize(.mini) }
                else { Text("\(model.quickResults.count) found").font(.caption2) }
            }.foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(model.quickResults.enumerated()), id: \.element.id) { index, session in
                            Button { model.openLibrary(sessionID: session.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 18, weight: .light)).foregroundStyle(session.agent == "Codex" ? .teal : .orange).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(session.title.isEmpty ? "Untitled conversation" : session.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        if !session.snippet.isEmpty { Text(session.snippet).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                                        HStack(spacing: 7) { Text(session.agent); Text("·"); Text(session.projectName.isEmpty ? "No repository" : session.projectName); Text("·"); Text(DateText.display(session.updated)) }.font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if model.quickSelection == index { Image(systemName: "return").foregroundStyle(.secondary).font(.caption) }
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(model.quickSelection == index ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(index)
                        }
                        if model.quickResults.isEmpty && !model.quickSearching {
                            VStack(spacing: 10) {
                                Image(systemName: model.importing ? "clock" : "magnifyingglass").font(.largeTitle).foregroundStyle(.tertiary)
                                Text(model.importing ? "Importing your history…" : "No conversations found").font(.callout)
                                Text(model.quickQuery.isEmpty ? "Import a transcript folder from the library." : "Try a topic, file path, commit, or PR URL.").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 65)
                        }
                    }.padding(.horizontal, 12)
                }.onChange(of: model.quickSelection) { _, value in withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) } }
            }
            Divider()
            HStack(spacing: 12) {
                Text("↑ ↓ Navigate    ↵ Open conversation").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Open Library") { model.openLibrary() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                Text("DocBrown").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.orange)
            }.padding(.horizontal, 24).padding(.vertical, 13)
        }
        .frame(width: 760, height: 540)
        .background(.regularMaterial)
        .onChange(of: model.quickQuery) { model.quickSelection = 0; model.searchQuickly() }
        .onMoveCommand { direction in
            if direction == .down { model.quickSelection = min(model.quickResults.count - 1, model.quickSelection + 1) }
            if direction == .up { model.quickSelection = max(0, model.quickSelection - 1) }
        }
        .onExitCommand { model.hideSearch() }
    }
}

private struct QuickSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: UUID
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> FocusTextField {
        let field = FocusTextField()
        field.font = .systemFont(ofSize: 23)
        field.placeholderString = "Search your coding history…"
        field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none; field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityIdentifier("quick-search")
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: FocusTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            field.focusWhenReady()
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickSearchField
        var focusToken: UUID?
        init(_ parent: QuickSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
    }
}
private final class FocusTextField: NSTextField {
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); focusWhenReady() }
    func focusWhenReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            window.makeFirstResponder(self)
        }
    }
}
