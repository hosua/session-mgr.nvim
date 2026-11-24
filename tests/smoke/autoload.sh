#!/usr/bin/env bash
# Screen-level smoke test of the startup question in a real TUI (tmux): the
# modal names the project, why, the session and when it was saved; Enter
# answers no and leaves nvim empty; y loads the file back.
set -euo pipefail
cd "$(dirname "$0")/../.."
source tests/smoke/lib.sh
SMOKE_ROOT=$(mktemp -d); export SMOKE_ROOT
mkdir -p "$SMOKE_ROOT/work"
echo hi >"$SMOKE_ROOT/work/a.txt"
: >"$SMOKE_ROOT/work/.session-root"
cd "$SMOKE_ROOT/work"
INIT="$OLDPWD/tests/smoke/autoload_init.lua"
rc=0

echo "-- run 1: nvim a.txt, quit (exit save)"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT" a.txt
smoke_keys ':qa' Enter
sleep 1

echo "-- run 2: plain nvim asks; Enter answers no"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_expect 'Load your last autosaved session\?' || rc=1
smoke_expect 'Project +~?/.*/work' || rc=1
smoke_expect 'Why +marker \.session-root' || rc=1
smoke_expect 'Session +autosave\.vim' || rc=1
smoke_expect 'Saved +(Just now|[0-9]+m)' || rc=1
smoke_expect 'y +load it' || rc=1
smoke_expect 'n +no, start empty \(default\)' || rc=1
smoke_keys Enter
smoke_expect 'Autosave not loaded\. Load it later with <leader>sL|:SessionMgr load!' || rc=1
smoke_reject 'hi' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys ':qa!' Enter
sleep 1

echo "-- run 3: plain nvim asks; y loads"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_expect 'Load your last autosaved session\?' || rc=1
smoke_keys y
smoke_expect 'hi' || rc=1
smoke_expect 'Loaded autosave \(marker \.session-root at' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys ':qa!' Enter

rm -rf "$SMOKE_ROOT"
exit "$rc"
