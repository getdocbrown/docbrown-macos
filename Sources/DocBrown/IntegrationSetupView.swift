import SwiftUI
#if canImport(DocBrownCore)
import DocBrownCore
#endif

struct IntegrationSetupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Connect your coding history", systemImage: "link").font(.title2.weight(.semibold))
            Text("DocBrown automatically reads local transcripts from Codex and Claude Code. Optional hooks request an immediate scan and record git context while you work.").font(.callout).foregroundStyle(.secondary)
            ForEach(HookProvider.allCases, id: \.rawValue) { provider in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(provider.name).font(.headline)
                        Spacer()
                        Button("Install Hooks") { model.configureHooks(provider, install: true) }
                        Button("Remove") { model.configureHooks(provider, install: false) }.disabled(!(model.hookStatuses[provider.rawValue] ?? "").hasPrefix("Configured"))
                    }
                    Text(model.hookStatuses[provider.rawValue] ?? "Checking…").font(.caption).foregroundStyle(.secondary)
                    Text(provider.config().path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
                }.padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            if !model.hookMessage.isEmpty { Text(model.hookMessage).font(.callout).textSelection(.enabled) }
            Text("Installation preserves existing hooks and settings and saves a backup. Review the new commands in your coding agent’s hook settings before they can run. DocBrown does not grant itself trust or change permissions.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Supported sources").font(.headline)
            Text("CLI and TUI sessions, plus desktop sessions that save local Codex or Claude Code transcripts. Cloud-only chats and remote machines need a local transcript export; they are not captured automatically.").font(.caption).foregroundStyle(.secondary)
            ForEach(model.roots, id: \.path) { root in
                Label(root.path, systemImage: FileManager.default.fileExists(atPath: root.path) ? "checkmark.circle.fill" : "circle.dashed").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack { Button("Import Another Folder…") { model.addFolder() }; Spacer(); Button("Open Library") { model.openLibrary() }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 650, height: 650).onAppear { model.refreshHookStatuses() }
    }
}
