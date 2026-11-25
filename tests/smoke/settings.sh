#!/usr/bin/env bash
# Screen-level smoke test of :SessionMgr settings in a real TUI (tmux): the
# menu shows each option with its value and where it comes from, the keys are
# in the border, Enter cycles and saves, x resets, e opens settings.json.
set -euo pipefail
cd "$(dirname "$0")/../.."
source tests/smoke/lib.sh
SMOKE_ROOT=$(mktemp -d); export SMOKE_ROOT
mkdir -p "$SMOKE_ROOT/work"
: >"$SMOKE_ROOT/work/.session-root"
cd "$SMOKE_ROOT/work"
INIT="$OLDPWD/tests/smoke/autoload_init.lua"
SETTINGS="$SMOKE_ROOT/sessions/settings.json"
rc=0

smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
smoke_keys ':SessionMgr settings' Enter
smoke_expect 'SessionMgr settings' || rc=1
smoke_expect 'autoload +prompt \(setup\)' || rc=1
smoke_expect 'j/k move +Enter cycle +x reset +e edit file +q/<Esc> dismiss ─*╯' || rc=1
smoke_reject 'E[0-9]+:' || rc=1

echo "-- Enter cycles to always and writes the file"
smoke_keys Enter
smoke_expect 'autoload +always \(settings file\)' || rc=1
grep -q '"autoload": "always"' "$SETTINGS" && echo "  ok    file has always" || { echo "  FAIL  $(cat "$SETTINGS" 2>&1)"; rc=1; }
smoke_keys Enter
smoke_expect 'autoload +never \(settings file\)' || rc=1

echo "-- x resets: the key goes, setup decides again"
smoke_keys x
smoke_expect 'autoload +prompt \(setup\)' || rc=1
grep -q autoload "$SETTINGS" && { echo "  FAIL  key still in file"; rc=1; } || echo "  ok    key removed"

echo "-- e opens settings.json in a split"
smoke_keys e
smoke_expect 'settings\.json' || rc=1
smoke_keys ':qa!' Enter
rm -rf "$SMOKE_ROOT"
exit "$rc"
