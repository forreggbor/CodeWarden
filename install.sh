#!/bin/bash

set -euo pipefail

INSTALL_PATH="/usr/local/bin/CodeWarden"

if ! command -v msgfmt &>/dev/null; then
    echo "Warning: 'msgfmt' not found. Install the 'gettext' package for PO compilation support."
fi

echo "Installing CodeWarden to $INSTALL_PATH..."
sudo cp CodeWarden.sh "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"
echo "Done. Run 'CodeWarden --help' to get started."
