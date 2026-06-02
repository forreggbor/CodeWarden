# Usage

## Synopsis

```bash
CodeWarden [OPTIONS]
```

## General Options

| Option             | Description                                    |
|--------------------|------------------------------------------------|
| `-d, --dir <path>` | Project base path (default: current directory) |
| `-y, --yes`        | Auto-confirm sensitive operations              |
| `-v, --version`    | Display version information                    |
| `--dry-run`        | Show what would happen without making changes  |
| `-h, --help`       | Display help message                           |

## Translation Intelligence & Localization

| Option                  | Description                                                                                                  |
|-------------------------|--------------------------------------------------------------------------------------------------------------|
| `-r, --restart`         | Compile PO files and restart PHP-FPM                                                                         |
| `-p, --po-path <path>`  | Override translation file path template (auto-detected by default)                                           |
| `-u, --unused [sub...]` | Analyze translations. Default: `sync`, `missing`, `unused`, `duplicates`, `dynamic`. Optional: `doconly`     |
| `-c, --cleanup`         | Comment out strictly unused keys (Gettext only; PHP-array translations are report-only)                      |
| `-f, --file`            | Save analysis report to file                                                                                  |

### Auto-detection of translation system

When `-u` runs, CodeWarden auto-detects the translation format — no CLI switch needed.
It probes candidate paths in this order, using **the first match found** for each language:

1. `locale/{LANG}/messages.php`
2. `webroot/locale/{LANG}/messages.php`
3. `locale/{LANG}/LC_MESSAGES/messages.po`
4. `webroot/locale/{LANG}/LC_MESSAGES/messages.po`

**PHP-array format** (`messages.php`) takes priority over Gettext when both exist.

Languages (`en_US`, `hu_HU`) are probed independently — if only one is found, the other is skipped
gracefully (no false "missing" reports). The detected mode and resolved file paths are printed at the
start of the analysis.

To override auto-detection, pass `-p` with a `{LANG}`-templated path. The mode is derived from
the file extension (`.php` → PHP-array, `.po` → Gettext):
```bash
CodeWarden -u -p "webroot/locale/{LANG}/messages.php"
```

### Sub-options for `-u`

| Sub-option   | Default | Description                                                            |
|--------------|---------|------------------------------------------------------------------------|
| `sync`       | yes     | Keys missing in one language file but present in the other             |
| `missing`    | yes     | Full keys found in code (PHP/JS) but not defined in translation files  |
| `unused`     | yes     | Keys defined in translation files but not used in code (PHP/JS)        |
| `duplicates` | yes     | Duplicate key entries within translation files                         |
| `dynamic`    | yes     | Dynamic prefixes (keys ending with `_`) used for concatenation in code |
| `doconly`    | no      | Keys found only in documentation files — must be explicitly specified  |

## System Operations

| Option                     | Description                                           |
|----------------------------|-------------------------------------------------------|
| `-o, --owner <user:group>` | Set file ownership recursively                        |
| `-m, --permissions`        | Fix permissions (dirs: 775, files: 664, scripts: 775) |
| `-n, --hostname <name>`    | Set local mDNS hostname via avahi                     |

## Examples

Analyze all translation issues (dry-run):
```bash
CodeWarden -d /var/www/myproject -u --dry-run
```

Check only unused and duplicate translations:
```bash
CodeWarden -u unused duplicates
```

Check dynamic prefixes and missing keys:
```bash
CodeWarden -u dynamic missing
```

Check keys used only in documentation:
```bash
CodeWarden -u doconly
```

Compile PO files and restart PHP-FPM:
```bash
CodeWarden -d /var/www/myproject -r
```

Fix ownership and permissions:
```bash
CodeWarden -d /var/www/myproject -o www-data:www-data -m
```

Full analysis with report saved to file:
```bash
CodeWarden -d /var/www/myproject -u -f
```

Set local mDNS hostname:
```bash
CodeWarden -n my-server
CodeWarden -n flowershop.local
```

## Translation Intelligence: Key Classification

| In Code (PHP/JS) | Dynamic Prefix | In translations | Classification             |
|------------------|----------------|-----------------|----------------------------|
| Yes              | -              | Yes             | ✓ OK (used correctly)      |
| Yes              | -              | No              | Missing from translations  |
| No               | Yes            | Yes             | ✓ Dynamically protected    |
| No               | No             | Yes             | Unused in code             |
| No               | -              | No              | Used only in documentation |

**Dynamic key**: ends with `_` (e.g., `ERROR_`) — a prefix used for string concatenation in code.

**Full key**: does NOT end with `_` (e.g., `ERROR_INVALID`) — must exist exactly in the translation file.

**Dynamically protected**: full keys that match a detected dynamic prefix. Example: `ERROR_INVALID` is protected when `ERROR_` is detected as a dynamic prefix in code.

### Dynamic Protection in practice

When code uses dynamic key construction:
```php
__('TEXT_STATUS_DELIVERY_' . strtoupper($status))
```

CodeWarden detects the `TEXT_STATUS_DELIVERY_` prefix and automatically protects all matching keys
(e.g., `TEXT_STATUS_DELIVERY_PENDING`, `TEXT_STATUS_DELIVERY_SHIPPED`) from being flagged as unused.

Prefixes that match ALL keys are excluded from dynamic detection — they represent naming conventions,
not dynamic usage (e.g., if every key starts with `TEXT_`, that prefix is ignored).

## Configuration

Default excluded directories: `vendor`, `.claude`, `database`, `locale`, `.idea`, `.git`

Default excluded files: `composer.*`, `.git*`

Root-level `/storage` directory is excluded from scanning; nested `**/storage` paths are not.

The `locale` directory exclusion applies both to standard (`locale/`) and non-standard
(`webroot/locale/`) layouts — translation files are never scanned as code.

Supported languages: `en_US`, `hu_HU`
