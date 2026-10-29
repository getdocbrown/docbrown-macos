# Architecture and verification

DocBrown has three targets: a shared Swift core, the SwiftUI/AppKit menu bar application, and a small CLI. SQLite and system frameworks are the only dependencies. Swift Package Manager runs the core tests; the checked-in Xcode project produces the native app.

## Capture and storage

`TranscriptImporter` owns a writer connection and runs off the UI actor. `AppModel` queries through a separate SQLite connection with WAL mode. Reads and writes use bound SQL parameters. Original JSONL records are archived byte-for-byte; source offsets, line numbers, modification dates, and prefix fingerprints support restart-safe, incremental imports. Batches archive and synchronize complete bytes before committing their database checkpoint. An incomplete trailing JSON record is retried next scan. A valid final JSON record without a newline is accepted.

Codex `response_item` records supply canonical messages and tool events. Mirrored `event_msg` messages are not imported twice. Claude blocks become individual text and tool entries while preserving UUID-based identity. Provider metadata identifies sessions and models. Unknown records remain in the archive; malformed lines are reported. Source rewrites preserve an earlier raw generation and refresh normalized content. A moved transcript uses stable session/record identity to avoid duplication.

`HookInstaller` merges explicitly requested handlers into JSON config, with exact command ownership for removal and backups before changes. A stable, private helper path avoids breakage when the application bundle moves. It does not approve hooks, change permissions, replace notification handlers, or modify repositories. `HookCapture` consumes JSON as data, invokes fixed git commands with argument arrays, writes raw snapshot records, and posts a local distributed notification. Disk snapshots survive periods when the app is not running. Polling remains the fallback.

The database stores sessions, messages, import checkpoints, source fingerprints, associations, git snapshots, and an FTS5 index. Search treats user input as literal tokens and escapes metadata matching. Query results open near matching context, with bounded message pagination and collapsed tool outputs to avoid loading entire large transcripts into SwiftUI views.

## Attribution

Recorded branch/HEAD facts are kept separate from arbitrary current repository state. A transcript reporting git commit creation is checked against the local repository before recording a confirmed commit. GitHub PR membership can then confirm a PR relationship. Branch matches are inferred; raw PR mentions are only references. Direct commit-to-PR lookup covers branch renames and PRs created later. No claim of complete provenance is made for squash/rebase operations that discard the available evidence.

Git and GitHub processes run with fixed argument arrays, time limits, noninteractive environment settings, and file-backed output to avoid pipe deadlocks. Transcript contents are never evaluated as commands. Only GitHub receives network requests, through the user's existing `gh` authentication. No transcript bodies are sent.

## Native application

The app uses accessory activation with `LSUIElement`, so it lives in the menu bar and does not occupy the Dock. A Carbon registered hotkey opens an AppKit floating panel containing the SwiftUI quick-search view. This does not require Accessibility or Input Monitoring permission. The full library and setup screens are ordinary windows created on demand. Escape dismisses quick search; keyboard navigation and Return open the selected result. Settings offers alternate shortcuts and login startup through `SMAppService`.

## Verification

The core suite exercises:

- Codex and Claude parsing, roles, models, tool blocks, and raw retention.
- Repeated import, moved sources, partial writes, no final newline, and restarts.
- Exclusions, removal tombstones, malformed and unknown records.
- FTS punctuation, metadata filters, and matching context beyond the first page.
- Internal review filtering and relationship confidence precedence.
- Branch-only inference and confirmed commit membership after a branch rename.
- Hook installation, idempotency, preservation of unrelated settings, exact removal, backups, invalid configuration rejection, and persisted git observations.

Release checks include the core suite, Xcode universal builds, bundle signature verification, live transcript import and SQLite integrity checks, then native UI checks for global invocation, search, keyboard result opening, full-library navigation, and setup. No user transcripts or runtime databases are part of the repository or release archive.
