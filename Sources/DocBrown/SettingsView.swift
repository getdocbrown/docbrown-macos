import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                Text("Checks quietly every six hours. You choose when to install and restart.").font(.caption).foregroundStyle(.secondary)
                Button(updater.menuTitle) { updater.checkForUpdates() }.disabled(!updater.canCheck)
                if let checked = updater.lastChecked { Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                if let error = updater.lastError { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
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
                Text("Codex and Claude Code history is imported automatically. No hooks or account setup are required.").font(.caption).foregroundStyle(.secondary)
                Button("Capture richer Git history…") { model.openSetup() }
                Text("Optional advanced integration: record the branch, commit, and changed-file list while you work, and update history sooner.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Collection") {
                Toggle("Include internal agent review sessions", isOn: $model.includeInternal)
                Toggle("Automatically collect new conversations", isOn: $model.automatic)
                Text("Checks for changes every 15 seconds while DocBrown is running. Closing the window keeps collection active in the menu bar.").font(.caption).foregroundStyle(.secondary)
                Toggle("Open DocBrown at login", isOn: $model.openAtLogin)
                if !model.loginItemError.isEmpty { Text(model.loginItemError).font(.caption).foregroundStyle(.secondary) }
                Button("Import Transcript Folder…") { model.addFolder() }
                if !model.customRoots.isEmpty {
                    ForEach(model.customRoots, id: \.self) { root in
                        HStack { Text(root).font(.caption).lineLimit(2); Spacer(); Button("Remove") { model.customRoots.removeAll { $0 == root }; UserDefaults.standard.set(model.customRoots, forKey: "customRoots") } }
                    }
                }
            }
            Section("Privacy & storage") {
                Text("No telemetry. No cloud account. No transcript content leaves this Mac. GitHub lookup uses your existing gh login to check repository and pull request activity.").font(.caption).foregroundStyle(.secondary)
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
            Section { Text("DocBrown 0.1.3 · Local-first conversation history").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(width: 620, height: 700)
    }
}
