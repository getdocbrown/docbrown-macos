# Architecture and verification

DocBrown has three targets: a shared Swift core, the SwiftUI/AppKit menu bar application, and a small CLI. The app embeds pinned Sparkle 2.10.1; the shared history core uses SQLite and system frameworks only. Swift Package Manager runs the core and AppKit keyboard tests; the checked-in Xcode project produces the native app.

## Capture and storage

`TranscriptImporter` owns a writer connection and runs off the UI actor. `AppModel` queries through a separate SQLite connection with WAL mode. Reads and writes use bound SQL parameters. Original JSONL records are archived byte-for-byte; source offsets, line numbers, modification dates, and prefix fingerprints support restart-safe, incremental imports. Batches archive and synchronize complete bytes before committing their database checkpoint. An incomplete trailing JSON record is retried next scan. A valid final JSON record without a newline is accepted.

Codex `response_item` records supply canonical messages and tool events. Mirrored `event_msg` messages are not imported twice. Claude blocks become individual text and tool entries while preserving UUID-based identity. Provider metadata identifies sessions and models. Unknown records remain in the archive; malformed lines are reported. Source rewrites preserve an earlier raw generation and refresh normalized content. A moved transcript uses stable session/record identity to avoid duplication.

`HookInstaller` merges explicitly requested handlers into JSON config, with exact command ownership for removal and backups before changes. A stable, private helper path avoids breakage when the application bundle moves. It does not approve hooks, change permissions, replace notification handlers, or modify repositories. `HookCapture` consumes JSON as data, invokes fixed git commands with argument arrays, writes raw snapshot records, and posts a local distributed notification. Disk snapshots survive periods when the app is not running. Polling remains the fallback.

The database stores sessions, messages, import checkpoints, source fingerprints, associations, git snapshots, cached GitHub PR activity, and an FTS5 index. Search treats user input as literal tokens and escapes metadata matching. Query results open near matching context, with bounded message pagination and collapsed tool outputs to avoid loading entire large transcripts into SwiftUI views.

## Attribution

Recorded branch/HEAD facts are kept separate from arbitrary current repository state. A transcript reporting git commit creation is checked against the local repository before recording a confirmed commit. GitHub PR membership can then confirm a PR relationship. Branch matches are inferred; raw PR mentions are only references. Direct commit-to-PR lookup covers branch renames and PRs created later. No claim of complete provenance is made for squash/rebase operations that discard the available evidence.

Git and GitHub processes run with fixed argument arrays, time limits, noninteractive environment settings, and file-backed output to avoid pipe deadlocks. Transcript contents are never evaluated as commands. Only GitHub receives network requests, through the user's existing `gh` authentication. No transcript bodies are sent.

Account-wide GitHub searches discover authored, reviewed, and commented PRs independently of transcript links. Each page is cached before fetching the next. A PR can appear in Your work with no local conversation; the UI labels that absence instead of inventing a relationship. Organization and repository filters apply to the activity list. Saved local Codex project names and folders are read without modifying Codex settings; non-Git folders and nested project roots are supported.

## Native application

The app uses accessory activation with `LSUIElement`, so it lives in the menu bar and does not occupy the Dock. A Carbon registered hotkey opens an AppKit floating panel containing the SwiftUI quick-search view. This does not require Accessibility or Input Monitoring permission. The full library and setup screens are ordinary windows created on demand. Escape dismisses quick search; keyboard navigation and Return open the selected result. Settings offers alternate shortcuts and login startup through `SMAppService`.

## Verification

The core suite exercises:

- Codex and Claude parsing, roles, models, tool blocks, and raw retention.
- Repeated import, moved sources, partial writes, no final newline, and restarts.
- Exclusions, removal tombstones, malformed and unknown records.
- FTS punctuation, relevance ranking, metadata filters, and matching context beyond the first page.
- Project discovery, multi-root and nested-folder filters, PR participation and ordering, account changes, and partial GitHub pagination failures.
- AppKit search-field and panel keyboard handling without opening visible windows.
- Internal review filtering and relationship confidence precedence.
- Branch-only inference and confirmed commit membership after a branch rename.
- Hook installation, idempotency, preservation of unrelated settings, exact removal, backups, invalid configuration rejection, and persisted git observations.

Release checks include the automated suites, Xcode universal app and CLI builds, bundle signature verification, and downloaded-asset checksums. Live import, SQLite integrity, and native UI checks also supported the initial build; routine feedback fixes are verified without opening windows or taking keyboard focus. No user transcripts or runtime databases are part of the repository or release archive.

## Updates

`AppUpdater` owns one Sparkle updater and publishes native menu/settings state. Its gentle-reminder delegate handles all scheduled update reminders, including launch-time reminders, without showing windows. Explicit checks use Sparkle's standard native UI. Automatic downloads/installations are disabled; automatic checks follow Sparkle's persisted preference and six-hour scheduler.

The appcast and archive use Ed25519 signatures, with pre-extraction verification. The app embeds only the public key. Releases are published only after all files are uploaded to a draft. A writable install is replaced in place by Sparkle's helper; a user-owned library is not part of the update payload. Termination during import cancels the current import and waits for its checkpoint before allowing exit.

`scripts/test-updater.py` uses Sparkle's real installer and generated app fixtures. It verifies installation, bad archive rejection, bad feed rejection, and download failure without visible UI or touching the installed app. The core test suite also interrupts and resumes an import, checking message counts, archive bytes, and database integrity.
