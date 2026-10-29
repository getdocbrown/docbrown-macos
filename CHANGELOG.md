# Changelog

## 0.1.2

- Quieter menu bar operation: opening at login is on by default, Command–D opens only quick search, and background launches no longer take focus.
- Polygon car and flaming tire tracks in the menu bar, plus a clearer Open DocBrown menu action.
- Relevance-ranked quick search with reliable arrow-key selection and clearer result highlighting.
- Saved Codex projects, non-Git folders, and multi-folder projects appear in the library; project filters include nested folders.
- Pull requests show recent account-wide work, including authored, reviewed, and commented PRs without a linked transcript. Organization/repository filters are visible, and mentions remain optional.
- GitHub activity loads incrementally, preserves cached results on partial failures, and keeps conversation attribution honest.
- Optional capture hooks live under Settings → Integrations as Capture richer Git history; normal history import needs no setup.

This release is ad-hoc signed and is not Apple-notarized.

## 0.1.1

- Refined native library with graphite and warm-paper surfaces, amber selection, a quieter sidebar, and a new welcome view.
- Readable Markdown conversations with headings, lists, tables, quotes, and code blocks.
- Collapsed environment/context envelopes and grouped tool activity; original messages remain inspectable and copyable.
- Compact conversation headers and PR references, with a comfortable reading width and clearer speaker hierarchy.
- Versioned release packaging and directly usable download checksums.

## 0.1.0

- Native macOS menu bar app with global Command–D quick search and configurable alternative shortcuts.
- Full conversation browser, agent/repository filters, source context, export, and PR timelines.
- Historical and incremental local Codex / Claude Code capture with SQLite FTS5 search and raw archives.
- Optional hook installation and removal with configuration backups and active git snapshots.
- Read-only git/GitHub enrichment with confirmed, inferred, observed, and referenced evidence.
- Local exclusions, deletion tombstones, optional login startup, and internal review filtering.
- Universal Apple silicon / Intel application and bundled CLI for macOS 14 and later.
