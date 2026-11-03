#!/usr/bin/env bash
# Symlink the plugin (and any spikes) into a KOReader desktop emulator build, so edits show up after a restart.
#
#   KOREADER_DIR   KOReader checkout (default: ~/Projects/koreader)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
koreader="${KOREADER_DIR:-$HOME/Projects/koreader}"

emulator=("${koreader}"/koreader-emulator-*)
if [[ ! -d "${emulator[0]}/koreader/plugins" ]]; then
    echo "No emulator build found in ${koreader}. See docs/DEVELOPMENT.md." >&2
    exit 1
fi

for plugin in "${repo}/mascot.koplugin" "${repo}"/spikes/*.koplugin; do
    ln -sfn "${plugin}" "${emulator[0]}/koreader/plugins/$(basename "${plugin}")"
    echo "Linked ${plugin}"
done
