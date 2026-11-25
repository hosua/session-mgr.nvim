#!/usr/bin/env bash
# Screen-level smoke test of the startup question in a real TUI (tmux): the
# menu names the project, why, the session and when it was saved, and lists
# its keys in the border. It starts on "Start empty" (so Enter answers no),
# j/k move the highlight and gg or the arrows do not, k then Enter loads the
# file back, Y writes settings.json and the next start loads without asking,
# N writes "never" and the next start does not ask. Shift+Enter is not sent:
# tmux cannot say which terminals report it, so it is covered by the spec.
set -euo pipefail
cd "$(dirname "$0")/../.."
source tests/smoke/lib.sh
SMOKE_ROOT=$(mktemp -d); export SMOKE_ROOT
mkdir -p "$SMOKE_ROOT/work"
echo hi >"$SMOKE_ROOT/work/a.txt"
: >"$SMOKE_ROOT/work/.session-root"
cd "$SMOKE_ROOT/work"
INIT="$OLDPWD/tests/smoke/autoload_init.lua"
SETTINGS="$SMOKE_ROOT/sessions/settings.json"
rc=0

echo "-- run 1: nvim a.txt, quit (exit save)"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT" a.txt
smoke_keys ':qa' Enter
sleep 1

echo "-- run 2: plain nvim asks; the layout, then Enter answers no"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_expect 'Load your last autosaved session\?' || rc=1
smoke_expect 'Project +~?/.*/work' || rc=1
smoke_expect 'Why +marker \.session-root' || rc=1
smoke_expect 'Session +autosave\.vim' || rc=1
smoke_expect 'Saved +(Just now|[0-9]+m)' || rc=1
smoke_expect 'Shift\+Enter, Y or N picks and never asks again \(:SessionMgr settings to change\)\.' || rc=1
smoke_expect '│ +Load it +│' || rc=1
smoke_expect '│ +Start empty +│' || rc=1
smoke_expect 'j/k move +⏎ pick +⇧⏎ pick\+remember +y load +n skip +Y always +N never +q/Esc cancel ─*╯' || rc=1
smoke_keys Enter
smoke_expect 'Autosave not loaded\. Load it later with <leader>sL|:SessionMgr load!' || rc=1
smoke_reject '^hi *$' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys ':qa!' Enter
sleep 1

echo "-- run 3: gg and the arrows leave the highlight on Start empty"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_expect 'Load your last autosaved session\?' || rc=1
smoke_keys g g Up Up Home
smoke_keys Enter
smoke_expect 'Autosave not loaded' || rc=1
smoke_reject 'Loaded autosave' || rc=1
smoke_keys ':qa!' Enter
sleep 1

echo "-- run 4: k moves to Load it, Enter loads"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_keys k
smoke_keys Enter
smoke_expect '^hi *$' || rc=1
smoke_expect 'Loaded autosave \(marker \.session-root at' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys ':qa' Enter
sleep 1

echo "-- run 5: y loads for this start only (no settings file yet)"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_keys y
smoke_expect 'Loaded autosave' || rc=1
smoke_reject 'Autoload is now' || rc=1
[ ! -e "$SETTINGS" ] && echo "  ok    no settings.json after y" || { echo "  FAIL  settings.json written by y"; rc=1; }
smoke_keys ':qa' Enter
sleep 1

echo "-- run 6: Y loads and remembers; the next start loads without asking"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_keys Y
smoke_expect 'Loaded autosave' || rc=1
smoke_expect 'Autoload is now "always"\. Change it with :SessionMgr settings' || rc=1
grep -q '"autoload": "always"' "$SETTINGS" && echo "  ok    settings.json has always" || { echo "  FAIL  settings.json: $(cat "$SETTINGS" 2>&1)"; rc=1; }
smoke_keys ':qa' Enter
sleep 1
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_reject 'Load your last autosaved session' || rc=1
smoke_expect '^hi *$' || rc=1
smoke_expect 'Loaded autosave' || rc=1
smoke_keys ':qa' Enter
sleep 1

echo "-- run 7: N remembers never; the next start does not ask and stays empty"
rm -f "$SETTINGS"
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_keys N
smoke_expect 'Autoload is now "never"' || rc=1
grep -q '"autoload": "never"' "$SETTINGS" && echo "  ok    settings.json has never" || { echo "  FAIL  settings.json: $(cat "$SETTINGS" 2>&1)"; rc=1; }
smoke_keys ':qa!' Enter
sleep 1
smoke_start 120 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u "$INIT"
sleep 1
smoke_reject 'Load your last autosaved session' || rc=1
smoke_reject '^hi *$' || rc=1
smoke_keys ':qa!' Enter

rm -rf "$SMOKE_ROOT"
exit "$rc"
