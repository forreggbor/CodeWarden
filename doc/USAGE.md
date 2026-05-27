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

## PO Intelligence & Localization

| Option                  | Description                                                                                          |
|-------------------------|------------------------------------------------------------------------------------------------------|
| `-r, --restart`         | Compile PO files and restart PHP-FPM                                                                 |
| `-p, --po-path <path>`  | Relative PO path (default: `locale/{LANG}/LC_MESSAGES/messages.po`)                                 |
| `-u, --unused [sub...]` | Analyze PO files. Default: `sync`, `missing`, `unused`, `duplicates`, `dynamic`. Optional: `doconly` |
| `-c, --cleanup`         | Comment out strictly unused keys                                                                     |
| `-f, --file`            | Save analysis report to file                                                                         |

### Sub-options for `-u`

| Sub-option   | Default | Description                                                            |
|--------------|---------|------------------------------------------------------------------------|
| `sync`       | yes     | Keys missing in one language file but present in the other             |
| `missing`    | yes     | Full keys found in code (PHP/JS) but not in PO files                  |
| `unused`     | yes     | Keys in PO files but not used in code (PHP/JS)                        |
| `duplicates` | yes     | Duplicate `msgid` entries within PO files                             |
| `dynamic`    | yes     | Dynamic prefixes (keys ending with `_`) used for concatenation in code |
| `doconly`    | no      | Keys found only in documentation files — must be explicitly specified  |

## System Operations

| Option                     | Description                                           |
|----------------------------|-------------------------------------------------------|
| `-o, --owner <user:group>` | Set file ownership recursively                        |
| `-m, --permissions`        | Fix permissions (dirs: 775, files: 664, scripts: 775) |
| `-n, --hostname <name>`    | Set local mDNS hostname via avahi                     |

## Examples

Analyze all PO issues (dry-run):
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

Full analysis with cleanup and report saved to file:
```bash
CodeWarden -d /var/www/myproject -u -c -f -y
```

Set local mDNS hostname:
```bash
CodeWarden -n my-server
CodeWarden -n flowershop.local
```

## PO Intelligence: Key Classification

| In Code (PHP/JS) | Dynamic Prefix | In PO | Classification             |
|------------------|----------------|-------|----------------------------|
| Yes              | -              | Yes   | ✓ OK (used correctly)      |
| Yes              | -              | No    | Missing from PO            |
| No               | Yes            | Yes   | ✓ Dynamically protected    |
| No               | No             | Yes   | Unused in code             |
| No               | -              | No    | Used only in documentation |

**Dynamic key**: ends with `_` (e.g., `ERROR_`) — a prefix used for string concatenation in code.

**Full key**: does NOT end with `_` (e.g., `ERROR_INVALID`) — must exist exactly in PO.

**Dynamically protected**: full keys that match a detected dynamic prefix. Example: `ERROR_INVALID` is protected when `ERROR_` is detected as a dynamic prefix in code.

### Dynamic Protection in practice

When code uses dynamic key construction:
```php
__('TEXT_STATUS_DELIVERY_' . strtoupper($status))
```

CodeWarden detects the `TEXT_STATUS_DELIVERY_` prefix and automatically protects all matching PO keys (e.g., `TEXT_STATUS_DELIVERY_PENDING`, `TEXT_STATUS_DELIVERY_SHIPPED`) from being flagged as unused or removed by cleanup.

Prefixes that match ALL keys are excluded from dynamic detection — they represent naming conventions, not dynamic usage (e.g., if every key starts with `TEXT_`, that prefix is ignored).

## Configuration

Default excluded directories: `vendor`, `.claude`, `database`, `locale`, `.idea`, `.git`

Default excluded files: `composer.*`, `.git*`

Root-level `/storage` directory is excluded from scanning; nested `**/storage` paths are not.

Supported languages: `en_US`, `hu_HU`
