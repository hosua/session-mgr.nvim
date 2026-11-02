#!/usr/bin/env bash
# Regenerates the autosave README media in docs/media/ with vhs, no AI needed.
# Fixtures live under a fixed /tmp path so frames show no home dir or hostname.
#   picker-autosave-on.tape   -> picker-autosave-on.png
#   picker-autosave-off.tape  -> picker-autosave-off.png
#   autoload.tape             -> autoload.png
#   new-session.tape          -> new-session.png
# Usage: bash docs/tapes/capture.sh [picker-autosave-on|picker-autosave-off|autoload|new-session]
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
DEMO=/tmp/session-mgr-demo
ONLY="${1:-}"

command -v vhs >/dev/null || {
    echo "error: vhs not found (sudo pacman -S vhs)" >&2
    exit 1
}

cd "${REPO}"
for tape in picker-autosave-on picker-autosave-off autoload new-session; do
    [ -z "${ONLY}" ] || [ "${ONLY}" = "${tape}" ] || continue
    # Fresh fixtures for every tape, so one run's saves never show in the next.
    rm -rf "${DEMO}"
    mkdir -p "${DEMO}/picker/work" "${DEMO}/auto/work"
    printf 'hello\n' >"${DEMO}/picker/work/a.txt"
    printf 'notes for the demo\nsecond line\n' >"${DEMO}/auto/work/a.txt"
    # Quitting once with a file open writes autosave.vim, which the autoload
    # tape then finds at startup.
    (cd "${DEMO}/auto/work" && DEMO_ROOT="${DEMO}/auto" nvim --headless --clean \
        -u "${REPO}/docs/tapes/init.lua" a.txt +qa)
    vhs "docs/tapes/${tape}.tape"
done
