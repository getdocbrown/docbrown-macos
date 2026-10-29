import SwiftUI

// System-aware graphite and warm paper; the same hierarchy works in both appearances.
enum Design {
    static func readable(_ value: String) -> String {
        guard let attributed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return value }
        return String(attributed.characters)
    }
    static let amber = Color(red: 1, green: 0.62, blue: 0.28)
    static let cyan = Color(red: 0.35, green: 0.79, blue: 0.81)
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let canvas = adaptive(dark: (0.080, 0.090, 0.105), light: (0.970, 0.964, 0.950))
    static let panel = adaptive(dark: (0.105, 0.116, 0.134), light: (0.993, 0.989, 0.978))
    static let raised = adaptive(dark: (0.132, 0.146, 0.165), light: (1, 1, 1))
    static let line = Color.primary.opacity(0.07)
    static func adaptive(dark: (Double,Double,Double), light: (Double,Double,Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

struct Eyebrow: View {
    let text: String
    var color: Color = Design.muted
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(color) }
}
struct AgentBadge: View {
    let agent: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(agent == "Codex" ? Design.cyan : Design.amber).frame(width: 5, height: 5)
            Text(agent).font(.system(size: 10, weight: .semibold))
        }.foregroundStyle(agent == "Codex" ? Design.cyan : Design.amber)
    }
}
struct KeyboardCap: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 3).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).stroke(Design.line)) }
}
