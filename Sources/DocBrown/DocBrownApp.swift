import SwiftUI

@main struct DocBrownApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        MenuBarExtra {
            Button("Search History…  \(model.hotkeyLabel)") { model.showSearch() }
            Button("Open DocBrown…") { model.openLibrary() }
            Divider()
            Text("\(model.sessionCount.formatted()) conversations indexed")
            Text(model.importing ? "Importing history…" : model.status)
            Button("Scan Now") { model.scan() }.disabled(model.importing)
            Button("Import Transcript Folder…") { model.addFolder() }
            Divider()
            SettingsLink()
            Button("Quit DocBrown") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: BrandAssets.menuBarImage)
                .renderingMode(.original)
                .accessibilityLabel("DocBrown")
        }
        Settings { SettingsView().environmentObject(model) }
            .commands {
                CommandGroup(after: .newItem) {
                    Button("Search History…") { model.showSearch() }
                    Button("Open Library") { model.openLibrary() }.keyboardShortcut("o", modifiers: [.command])
                    Button("Import Transcript Folder…") { model.addFolder() }.keyboardShortcut("i", modifiers: [.command, .shift])
                    Button("Scan for New Conversations") { model.scan() }.keyboardShortcut("r", modifiers: .command)
                }
                CommandGroup(after: .saveItem) {
                    Button("Export Conversation…") { model.exportSelected() }.disabled(model.selectedID == nil)
                }
                CommandGroup(replacing: .help) {
                    Button("Open DocBrown Guide") { if let url = URL(string: "https://github.com/getdocbrown/docbrown-macos#readme") { NSWorkspace.shared.open(url) } }
                }
            }
    }
}
