import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    var body: some View {
        Form {
            Section("Quick search") {
                Picker("Global shortcut", selection: $model.hotkeyChoice) {
                    Text("⌘D — Command–D (default)").tag("command-d")
                    Text("⌃⌥⌘D — Control–Option–Command–D").tag("control-option-command-d")
                    Text("⌃⌥Space — Control–Option–Space").tag("control-option-space")
                    Text("⌃⌥D — Control–Option–D").tag("control-option-d")
                    Text("⌃⇧D — Control–Shift–D").tag("control-shift-d")
                }
                Text("Works from any app. Press Escape to dismiss; Return opens the selected conversation in the library.").font(.caption).foregroundStyle(.secondary)
                if !model.hotkeyError.isEmpty { Text(model.hotkeyError).font(.caption).foregroundStyle(.red) }
                Button("Open Quick Search") { model.showSearch() }
            }
            Section("Integrations") {
                Button("Set Up Codex & Claude Code Capture…") { model.openSetup() }
            }
            Section("Collection") {
                Toggle("Include internal agent review sessions", isOn: $model.includeInternal)
                Toggle("Automatically collect new conversations", isOn: $model.automatic)
                Text("Checks for changes every 15 seconds while DocBrown is running. Closing the window keeps collection active in the menu bar.").font(.caption).foregroundStyle(.secondary)
                Toggle("Open DocBrown at login", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { loginError = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.red) }
                Button("Import Transcript Folder…") { model.addFolder() }
                if !model.customRoots.isEmpty {
                    ForEach(model.customRoots, id: \.self) { root in
                        HStack { Text(root).font(.caption).lineLimit(2); Spacer(); Button("Remove") { model.customRoots.removeAll { $0 == root }; UserDefaults.standard.set(model.customRoots, forKey: "customRoots") } }
                    }
                }
            }
            Section("Privacy & storage") {
                Text("No telemetry. No cloud account. No transcript content leaves this Mac. GitHub lookup uses your existing gh login and sends repository names only.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Library") { Text(model.paths.directory.path).font(.caption).textSelection(.enabled) }
                Button("Show Library in Finder") { NSWorkspace.shared.open(model.paths.directory) }
                Text("Exclude working directories (one absolute path per line)").font(.caption)
                TextEditor(text: $model.excludedText).font(.system(size: 11, design: .monospaced)).frame(height: 70)
                Button("Save Exclusions") { model.saveExclusions() }
                Text("Exclusions prevent future imports. Remove previously imported conversations using their ••• menu. Source transcripts are never changed.").font(.caption2).foregroundStyle(.secondary)
            }
            Section("GitHub relationships") {
                Button("Refresh Pull Requests") { model.refreshGitHub() }.disabled(model.refreshingGitHub)
                if !model.githubStatus.isEmpty { Text(model.githubStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            if !model.importErrors.isEmpty {
                Section("Import issues") { ForEach(model.importErrors, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } }
            }
            Section { Text("DocBrown 0.1.0 · Local-first conversation history").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 620, height: 700)
    }
}
