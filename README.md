# DocBrown

**Pick up where you left off.**

DocBrown is a native, local-first macOS menu bar app for finding the conversations behind your code. It imports Codex and Claude Code history, connects it to git and pull requests, and makes it searchable without an account or a hosted service.

## Run v0.1.3

Download **DocBrown-0.1.3-macOS.zip** from [Releases](https://github.com/getdocbrown/docbrown-macos/releases), unzip it, and move **DocBrown.app** to Applications. Requires macOS 14 Sonoma or newer; the app and bundled CLI support Apple silicon and Intel.

Open DocBrown, then press **⌘D** from any app. Type to search, use **↑/↓** to select a result, and press **Return** to open its conversation. **Escape** dismisses quick search. The default shortcut takes over Command–D while DocBrown runs; change it in Settings if you use that shortcut elsewhere.

DocBrown lives in the menu bar, with no Dock icon. Choose **Open DocBrown…** for the full browser, repository and agent filters, readable transcripts, and pull request timelines. Closing a window keeps collection running. Choose **Quit DocBrown** in the menu bar to stop it. Launch at login is enabled by default and can be turned off in Settings. Launch and reopen events stay quiet. Quick search opens only from its shortcut or menu action, as a nonactivating panel; the full library opens only from **Open DocBrown…** or by choosing a result.

The v0.1.3 download is ad-hoc signed, not Apple-notarized. A downloaded copy may require approval in macOS **System Settings → Privacy & Security → Open Anyway**. Locally built copies run directly. There is no Developer ID certificate bundled with the project.

## Updates

Choose **Update DocBrown…** from the menu bar or Settings. Automatic checks are on by default and run quietly every six hours; an available version changes the menu label without opening a window or taking focus. You choose when to download, install, and restart. Turn off automatic checks in Settings if preferred.

Sparkle 2.10.1 verifies the signed feed and update archive before extraction. Updates preserve the library, preferences, and hook configuration. The first updater-enabled release is 0.1.3: versions 0.1.2 and earlier need one manual installation. Downloads and update metadata are hosted on GitHub; no GitHub login is needed for updates.

## Connect your history

Historical import starts automatically. Default locations are:

- `~/.codex/sessions` and `~/.codex/archived_sessions`
- `~/.claude/projects`

`CODEX_HOME` and `CLAUDE_CONFIG_DIR` are respected when present in the app’s environment. Finder-launched applications do not inherit your shell configuration; use **Import Transcript Folder** for other locations.

Automatic import requires no setup. For optional, richer Git history, open **Settings → Integrations → Capture richer Git history…**. Hooks record the branch, commit, and changed-file list while you work and request faster updates. The installer adds `SessionStart`, `PostToolUse`, and `Stop` handlers to Codex’s `hooks.json` or Claude Code’s `settings.json`, preserving other settings and hooks and saving backups. The stable capture helper is copied into DocBrown’s private application support directory.

**Review and approve the new hooks in the coding agent’s own hook settings.** DocBrown never grants itself trust or changes agent permissions. Restart or begin a new agent session when required. The setup screen can remove only DocBrown’s handlers without removing other hooks.

Hooks record git snapshots and notify the running app to scan promptly. Without hooks, new history is discovered every 15 seconds while DocBrown runs. Hooks are optional; importing does not depend on them.

| Source | Support |
| --- | --- |
| Codex CLI / TUI | Local JSONL transcripts; optional current lifecycle hooks |
| Codex desktop and editor sessions | Sessions written to the local Codex transcript directories |
| Claude Code CLI / TUI | Local JSONL transcripts; optional lifecycle hooks |
| Claude Code in desktop/editor apps | Supported when the client saves standard local Claude Code transcripts |
| Ordinary ChatGPT / Claude cloud chats | Not captured automatically |
| Remote machines and cloud agent sessions | Import their exported local transcripts; no remote collection service |

See the [Codex hook documentation](https://developers.openai.com/codex/hooks) and [Claude Code hook documentation](https://code.claude.com/docs/en/hooks) for provider support and approval behavior. Older clients without lifecycle hooks still work through transcript discovery.

## Search and attribution

The project list combines saved local Codex projects with folders discovered in conversation history. Projects do not need to be Git repositories, and saved projects appear even before their first conversation. Selecting a project includes history in its configured folders and their subfolders.

Search words, phrases, file paths, commit hashes, or PR numbers/URLs. Search uses SQLite FTS5 plus repository and relationship metadata. Results show excerpts and open near the first matching message, including surrounding context. A focused reading view renders Markdown headings, lists, tables, quotes, and code. Environment envelopes are folded into context rows, and consecutive tool calls form expandable activity groups. Original source remains available from the message menu. Long conversations load in pages; tool calls and results can be expanded. Original messages can be copied or exported as Markdown.

Repository and branch information is captured when available in transcripts or hooks. Existing local checkouts supply repository roots and remote URLs. Missing or deleted checkouts do not prevent transcript import.

PR relationships carry evidence:

- **Confirmed:** a git commit creation result appears in the session, and GitHub reports that commit in the PR.
- **Inferred:** a recorded session branch matches the PR branch. Branch reuse, rebases, squashes, and manual work can make that relationship uncertain.
- **Referenced:** the transcript mentions a PR URL. A mention is not proof of contribution.
- **Observed:** a hook captured a git snapshot. Observing HEAD does not prove the session created that commit.

Optional GitHub enrichment uses the existing `gh` login, performs read-only requests, and refreshes periodically. It sends repository identifiers, commit hashes, and the account login for participation queries, never conversation text. Authentication failure is reported in Settings and does not interrupt local search. Branch discovery checks up to 500 recent PRs per repository; direct commit lookup also finds PRs after branch renames and later PR creation. Squashed commits without surviving membership may remain inferred.

The pull-request sidebar defaults to **Your work**: PRs you authored, reviewed, commented on, or contributed confirmed commits to. GitHub activity is discovered across repositories, including PRs without a linked local conversation. It sorts by the latest GitHub update, falling back to the latest linked conversation when GitHub dates are unavailable. The filter menu narrows by organization and repository; **All activity** also includes mentions and inferred branch matches. The active scope is always shown below the filter. Each row explains why it is included. Participation is checked using the active GitHub account, with up to 500 recent results for each activity type. Existing conversation-to-PR evidence retains its original confidence label; no conversation link is invented for a GitHub-only PR.

Internal Codex approval-review conversations are hidden by default. Include them in Settings if desired.

## Privacy and storage

The SQLite database, raw transcript copies, hook event records, and configuration backups stay in:

```
~/Library/Application Support/DocBrown/
```

No telemetry, hosted database, embedding API, or LLM is used. Original source files and repositories are read-only. Raw records are retained so parsing can improve without losing evidence. Large histories need additional disk space for this archive and search index.

Settings supports excluded working directories. Exclusions stop future collection for those paths; use a conversation’s **••• → Remove from Library** action to erase previously imported history. Removal also creates a local tombstone so automatic import will not immediately restore that source. Original agent transcripts are untouched. Raw generations and hook snapshots for that conversation are removed too.

## Build and test

Open **DocBrown.xcodeproj** in Xcode and run the **DocBrown** scheme. The app launches into the menu bar; press **⌘D**. The Xcode project has no third-party dependencies.

```sh
swift test
./scripts/build-release.sh
open build/DocBrown.app
```

The release script builds a universal app and CLI, signs the bundle locally, and produces `build/DocBrown-0.1.3-macOS.zip` plus checksums. Sparkle is pinned in both package manifests. Regenerate the checked-in Xcode project with `python3 scripts/generate-project.py` after adding source files. See [architecture and verification](docs/ARCHITECTURE.md).

## CLI

The app includes `Contents/Helpers/docbrown`. You can call it directly or add your own shell alias:

```sh
/Applications/DocBrown.app/Contents/Helpers/docbrown search "authentication redirect"
/Applications/DocBrown.app/Contents/Helpers/docbrown pr 377
/Applications/DocBrown.app/Contents/Helpers/docbrown file src/auth/login.tsx
/Applications/DocBrown.app/Contents/Helpers/docbrown session 'Codex:session-id'
/Applications/DocBrown.app/Contents/Helpers/docbrown stats
```

`import [FOLDER...]` performs an incremental import; `github` refreshes PR relationships. Use `--library PATH` for a separate library. Swift Package Manager names the standalone development executable `docbrown-cli` to avoid a case-insensitive filesystem collision with `DocBrown`.

## v0.1.3 boundaries

This release provides keyword search, not semantic search or generated answers. It does not recover encrypted reasoning, cloud-only conversations, attachments that are unavailable locally, or git provenance absent from both the transcript and hooks. Attribution uncertainty is shown rather than invented. MCP, cloud sync, and team features are outside this release.

## Publishing updates

Run `scripts/build-release.sh`, then `scripts/generate-appcast.sh`. Local signing uses the `ai.docbrown.macos.sparkle` Keychain account. CI uses the repository's `SPARKLE_PRIVATE_KEY` secret; never commit or log this key. The public key is embedded in `Resources/Info.plist`. Back up the Keychain securely: replacing the signing key requires an intentional migration.

The release workflow tests the app and the real Sparkle installer against isolated fixtures, generates a signed `appcast.xml`, uploads the complete release as a draft, then publishes it. The stable feed URL is `https://github.com/getdocbrown/docbrown-macos/releases/latest/download/appcast.xml`. Do not edit the generated XML or ZIP after signing, and do not publish a stable release without its signed feed. `CFBundleVersion` must increase for every release.

The current ad-hoc build uses a library-validation exception to load Sparkle. When Developer ID signing and notarization are introduced, remove that exception and verify an upgrade from the previous public build. Sparkle and its third-party license notices are bundled in the app.
