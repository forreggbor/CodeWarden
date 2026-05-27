# CodeWarden

A bash utility for PHP project maintenance — localization analysis, file ownership, permissions, and system configuration.

## Features

- **PO Intelligence**: detect unused, missing, duplicate, and out-of-sync translation keys across `hu_HU` / `en_US`
- **Dynamic prefix tracking**: keys assembled via string concatenation are protected from false-positive "unused" reports
- **PO compilation**: validate and compile `.po` → `.mo`, then restart PHP-FPM
- **Cleanup**: comment out strictly unused translation keys (with dry-run support)
- **Ownership & permissions**: set `user:group` and apply standard permission masks recursively
- **Hostname**: set local mDNS hostname via `hostnamectl` + `avahi-daemon`

## Requirements

- Bash 4+
- `gettext` (for `msgfmt` — PO compilation only)
- `sudo` access (for FPM restart, ownership, permissions, and hostname changes)

## Installation

```bash
git clone https://github.com/forreggbor/CodeWarden.git
cd CodeWarden
sudo bash install.sh
```

Or copy manually:
```bash
sudo cp CodeWarden.sh /usr/local/bin/CodeWarden
sudo chmod +x /usr/local/bin/CodeWarden
```

## Quick Start

```bash
# Analyze all translation issues in a project
CodeWarden -d /var/www/myproject -u

# Compile PO files and restart PHP-FPM
CodeWarden -d /var/www/myproject -r

# Fix ownership and permissions
CodeWarden -d /var/www/myproject -o www-data:www-data -m
```

For the full option reference, examples, and PO intelligence details see [doc/USAGE.md](doc/USAGE.md).

## License

MIT
