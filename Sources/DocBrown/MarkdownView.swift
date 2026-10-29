import SwiftUI
#if canImport(DocBrownCore)
import DocBrownCore
#endif

struct MarkdownView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(MarkdownBlock.parse(text)) { block in
                switch block.kind {
                case .paragraph:
                    inline(block.text).font(.system(size: 15)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                case .heading(let level):
                    inline(block.text).font(.system(size: level == 1 ? 25 : level == 2 ? 21 : 17, weight: .semibold)).tracking(-0.3).padding(.top, level < 3 ? 9 : 4)
                case .bullet(let marker):
                    HStack(alignment: .top, spacing: 12) {
                        Text(marker).foregroundStyle(Design.amber).font(.system(size: 14, weight: .medium)).frame(minWidth: 15, alignment: .leading)
                        inline(block.text).font(.system(size: 15)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    }
                case .quote:
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 2).fill(Design.amber.opacity(0.7)).frame(width: 3)
                        inline(block.text).font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(5).padding(.vertical, 6)
                    }.fixedSize(horizontal: false, vertical: true)
                case .code(let language): CodeBlock(text: block.text, language: language)
                case .table(let rows):
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
                            ForEach(rows.indices, id: \.self) { index in
                                GridRow {
                                    ForEach(rows[index].indices, id: \.self) { column in
                                        inline(rows[index][column]).font(.system(size: 12, weight: index == 0 ? .semibold : .regular)).padding(.vertical, 11)
                                    }
                                }
                                if index < rows.count - 1 { Rectangle().fill(Design.line).frame(height: 1).gridCellUnsizedAxes(.horizontal) }
                            }
                        }.padding(.horizontal, 15)
                    }.background(Design.panel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Design.line))
                case .rule: Rectangle().fill(Design.line).frame(height: 1).padding(.vertical, 5)
                }
            }
        }.textSelection(.enabled).tint(Design.cyan).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func inline(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) { return Text(attributed) }
        return Text(value)
    }
}

struct CodeBlock: View {
    let text: String
    var language = ""
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(.secondary.opacity(0.3)).frame(width: 5, height: 5) } }
                Text(language.isEmpty ? "CODE" : language.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary).padding(.leading, 5)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); copied = true } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.horizontal, 15).padding(.vertical, 11).background(.primary.opacity(0.025))
            Rectangle().fill(Design.line).frame(height: 1)
            ScrollView(.horizontal) {
                Text(text).font(.system(size: 12, design: .monospaced)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: true, vertical: false).padding(16)
            }
        }.background(Design.canvas).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Design.line))
    }
}
