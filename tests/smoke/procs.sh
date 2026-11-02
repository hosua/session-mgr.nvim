#!/usr/bin/env bash
# Screen-level smoke test of the Processes tab in a real TUI (see lib.sh).
# Reads the live process table, so it only checks things true on any Linux
# box running it: the nvim under test is listed and marked as ours.
set -euo pipefail
cd "$(dirname "$0")/../.."
source tests/smoke/lib.sh
[ -d /proc/self ] || {
    echo "  skip  no /proc"
    exit 0
}
SMOKE_ROOT=$(mktemp -d)
export SMOKE_ROOT
mkdir -p "$SMOKE_ROOT/work"
echo hi >"$SMOKE_ROOT/work/a.txt"
rc=0
smoke_start 160 32 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u tests/smoke/init.lua
smoke_keys ':SessionMgr procs' Enter
sleep 1.5
smoke_expect 'nvim processes' || rc=1
smoke_expect 'PID +Tree ▼ +PSS +Thr +CPU% +Command' || rc=1
smoke_expect 'x term  X kill tree  ␣ mark  ⏎ fold' || rc=1
smoke_keys /
smoke_type 'smoke/init.lua'
smoke_keys Enter
smoke_expect '/ smoke/init.lua' || rc=1
smoke_expect '● +[0-9]+ .*nvim --clean -u tests/smoke/init.lua' || rc=1
smoke_reject 'ps -eo' || rc=1
smoke_keys Space
smoke_expect '1 marked' || rc=1
smoke_keys k
smoke_keys x
smoke_expect 'Send SIGTERM\?' || rc=1
smoke_expect 'this includes the nvim you are typing in' || rc=1
smoke_keys q
smoke_reject 'Send SIGTERM' || rc=1
smoke_keys '?'
smoke_expect 'SIGKILL the process and everything below it' || rc=1
smoke_reject 'rename' || rc=1
smoke_keys q
smoke_keys Tab
smoke_expect 'Load a session for' || rc=1
smoke_resize 80 24
smoke_keys BTab # tmux's name for shift-tab
smoke_expect 'nvim processes' || rc=1
smoke_expect '╰ x term  X kill tree' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_stop
rm -rf "$SMOKE_ROOT"
exit $rc
