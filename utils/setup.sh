#!/bin/sh
# Make all check scripts executable

SCRIPT_DIR=$(dirname "$0")

chmod +x "$SCRIPT_DIR/check-posix"
chmod +x "$SCRIPT_DIR/binaries"/check_*

echo "All scripts are now executable"
