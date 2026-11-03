#!/usr/bin/env bash
# Link the plugin and start the KOReader desktop emulator (without rebuilding it).
# Extra arguments go to `kodev run`, e.g. scripts/dev-run.sh -s kobo-clara
#
#   KOREADER_DIR   KOReader checkout (default: ~/Projects/koreader)
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
koreader="${KOREADER_DIR:-$HOME/Projects/koreader}"

"${here}/dev-link.sh"
cd "${koreader}"
exec ./kodev run --no-build -s kindle-paperwhite "$@"
