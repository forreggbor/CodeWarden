# Changelog

All notable changes to this project will be documented in this file.

## [v1.08.01] - 2026-09-18

| Category | Description                                                          |
|----------|-----------------------------------------------------------------------|
| Changed  | `storage` and `doc` are now excluded from scans by default, like `vendor`/`database` |

### Changed
- `storage` and `doc` directories are now excluded from scans by default, at any depth —
  the same "excluded by name, anywhere in the tree" rule already applied to `vendor`,
  `database`, and `locale`. A project isn't expected to keep scannable code inside either,
  and they're exactly where large binary content (backups, generated PDFs, reference
  material) tends to accumulate. Replaces the previous root-level-only `storage/`
  post-filter, which excluded matches from the report but still had to read every
  scanned byte to find them.

## [v1.08.00] - 2026-09-18

| Category | Description                                                                     |
|----------|-----------------------------------------------------------------------------------|
| Added    | `-L`/`--lib-locales` treats `lib/*/locale/{LANG}/messages.php` keys as defined    |
| Fixed    | Missing-key detection no longer flags non-translation string literals             |
| Fixed    | Missing-key detection now recognizes `'PREFIX' . $var . 'SUFFIX'` concatenation   |
| Fixed    | Scans no longer stall for minutes on projects with large binary content           |

### Added
- New `-L`/`--lib-locales` flag: also loads `lib/*/locale/{LANG}/messages.php` (the
  Reusables vendored-module convention) as a valid source of key definitions for the
  Missing, Dynamic Matches, and Duplicate Definitions checks. Deliberately excluded from
  the Sync Check (stays scoped to the project's own HU/EN pair) and from the Unused check
  (a key unused by this project may still be used by another project sharing the same
  module — only that module's own source repository can answer "is this dead code").
  PHP-array projects only; a Gettext project prints a warning and ignores the flag.

### Fixed
- Key detection now requires the matched token to be a whole quoted-string literal, not
  just any `TEXT_`-shaped run of characters anywhere in a file. This removes false
  "missing" reports for things that were never a translation call in the first place:
  PHPDoc example text, JS/PHP constant access (`Node.TEXT_NODE`, `MyClass::TEXT_X`).
- `'PREFIX' . $var . 'SUFFIX'` string concatenation (a variable spliced into the middle
  of two literal halves) is now recognized as dynamic key construction, the same way
  `'PREFIX_' . $var` already was. Previously the literal `PREFIX` half was reported as a
  static, missing key even when the real (suffixed) keys existed.
- Recursive scans no longer read the full content of binary files (backups, PDFs,
  images, archives) looking for key matches. A project that keeps several gigabytes of
  such content under a scanned path could previously turn a sub-second scan into one
  that took many minutes, or appeared to hang.

## [v1.07.00] - 2026-06-02

| Category | Description                                                                     |
|----------|---------------------------------------------------------------------------------|
| Added    | Animated progress spinner for all active sections                               |
| Added    | Twig and SQL files are now scanned for translation key usage                    |
| Changed  | PHP-FPM restart auto-detects the running version instead of using a fixed name  |

### Added
- Animated braille spinner shows live progress during long-running operations (translation scan, PO compile, FPM restart, ownership, permissions, hostname apply); each section displays a phase label while work is in progress
- Spinner output goes to stderr only — the analysis report and any file output (`-f`) are unaffected
- Degrades gracefully when stderr is not a TTY (CI, pipes, redirected output): prints a single plain-text label per phase, no ANSI escape codes
- Cursor is automatically restored on exit, interrupt (Ctrl-C), and termination signals — no stray background processes or hidden cursors left behind
- Translation key usage is now detected in Twig template files (`.twig`) — keys found in templates are treated as used, same as PHP and JS
- Translation key usage is now detected in SQL files (`.sql`) — keys stored as values in schema or migration files are treated as used and not flagged as orphaned

### Changed
- PHP-FPM restart (`-r`) auto-detects the active service name instead of using the hardcoded `php8.4-fpm`; selects the highest-versioned running instance, with fallback to active and then installed units

## [v1.06.00] - 2026-06-02

| Category | Description                                                              |
|----------|--------------------------------------------------------------------------|
| Added    | PHP-array translation support with automatic system detection            |
| Changed  | Single-language sync, cleanup safety for PHP, labels                     |

### Added
- Translation key checks now work with PHP-array files (`locale/{LANG}/messages.php`, `webroot/locale/{LANG}/messages.php`) in addition to Gettext `.po` files — all six sub-checks (sync, missing, unused, duplicates, dynamic, doconly) function identically for both formats
- Automatic translation system detection: CodeWarden probes PHP-array paths first, then Gettext paths, with no CLI switch required; the detected mode and resolved file paths are printed at the start of the analysis
- Single-language projects are now handled gracefully — when only one language file exists (e.g., only `hu_HU`), the sync check reports "skipped" instead of flagging all keys as missing in the other language

### Changed
- `-p` flag now accepts PHP file path templates (e.g., `locale/{LANG}/messages.php`) in addition to PO paths; the translation mode is derived automatically from the file extension
- Cleanup (`-c`) reports "not supported for PHP-array translations" and skips for PHP-array projects; Gettext cleanup behavior is unchanged
- Section header and report labels updated from "PO Intelligence" to "Translation Intelligence" to reflect support for both formats

## [v1.05.01] - 2026-02-26

| Type    | Count |
|---------|-------|
| Added   | 0     |
| Changed | 0     |
| Fixed   | 1     |
| Removed | 0     |

### Fixed
- Hostname validation now accepts dot-separated FQDN labels (e.g. `flowershop.local`) in addition to single-label hostnames

## [v1.05.00] - 2026-02-25

| Type    | Count |
|---------|-------|
| Added   | 2     |
| Changed | 0     |
| Fixed   | 0     |
| Removed | 0     |

### Added
- `-n, --hostname <name>` switch to set local mDNS hostname via `hostnamectl` and restart `avahi-daemon`
- RFC 1123 hostname format validation (alphanumeric and hyphens, no leading/trailing hyphens, max 63 chars)

## [v1.04.00] - 2026-01-27

### Added
- Dynamic prefix linking: Keys matching detected dynamic prefixes are now marked as "dynamically protected"
- Protected key count shown per dynamic prefix (e.g., `TEXT_STATUS_DELIVERY_ | 3 keys protected`)
- Summary now shows count of dynamically protected keys

### Changed
- `doconly` sub-option no longer runs by default with `-u`; must be explicitly specified (`-u doconly`)

### Fixed
- Keys like `TEXT_STATUS_DELIVERY_PENDING` no longer flagged as unused when `TEXT_STATUS_DELIVERY_` prefix is used in code via concatenation (e.g., `__('TEXT_STATUS_DELIVERY_' . strtoupper($status))`)
- Prefixes matching ALL keys (naming conventions like `TEXT_`) are now excluded from dynamic detection
- Cleanup (`-c`) no longer comments out dynamically protected keys

## [v1.03.00] - 2026-01-27

### Added
- New "Dynamic Matches" section for keys ending with `_` (prefixes used for concatenation)
- New "Used Only in Documentation" section for keys in docs but not in PO or code
- New sub-options: `dynamic` and `doconly` for `-u` switch
- Doc-only count in summary
- Empty line before each sub-section header for better readability

### Changed
- Complete rewrite of key classification logic
- Keys are now properly categorized: code (PHP/JS), docs, or PO
- "Unused in Code" section now correctly shows keys in PO but not used in code
- "Missing from PO" section now only shows full keys (not dynamic prefixes)
- Improved tracking prevents keys from appearing in wrong sections
- Storage directory exclusion now only applies to root-level `/storage` (not `**/storage`)

### Fixed
- Keys marked `[used in: md]` when actually also used in code
- Dynamic prefixes (ending with `_`) no longer listed under "Missing from PO"
- Keys in paths like `app/views/.../storage/file.php` are now properly scanned

## [v1.02.00] - 2026-01-27

### Added
- Missing keys count in summary (keys found in code but not in PO files)

### Removed
- "Dynamic Matches" section that incorrectly marked keys as safe based on prefix matching

### Fixed
- Keys like `ERROR_INVALID` no longer incorrectly marked as "safe" just because `ERROR_` prefix exists in code

## [v1.01.00] - 2026-01-18

### Added
- `--version` flag to display version information
- `require_arg()` validation for options requiring arguments
- `escape_regex()` helper for safe sed operations
- Owner format validation (user:group)
- Directory permissions (775) in permission fixing
- Confirmation prompt for cleanup (bypass with `-y`)
- Success/failure status output for all sections

### Fixed
- `LANG` variable renamed to `LANG_CODE` to avoid shadowing system locale
- Empty PO file handling with warning message
- Array globbing vulnerability replaced with `mapfile`
- Regex metacharacters now escaped in cleanup sed commands
- Added dry-run messages for all operations

### Changed
- Unknown arguments now show warning instead of silent ignore
- Unknown sub-options for `-u` now show warning

## [v1.00.00] - 2026-01-18

### Added
- PO compilation and PHP-FPM restart functionality
- PO intelligence analysis (sync, missing, unused, duplicates)
- Cleanup feature to comment out unused translation keys
- File ownership management
- File permission fixing (664/775)
- Dry-run mode
- Report file output option
