#!/usr/bin/env bash
# Screen-level smoke test of the save popup in a real TUI (tmux).
set -euo pipefail
cd "$(dirname "$0")/../.."
source tests/smoke/lib.sh
SMOKE_ROOT=$(mktemp -d); export SMOKE_ROOT
mkdir -p "$SMOKE_ROOT/work"; echo hi >"$SMOKE_ROOT/work/a.txt"
rc=0
smoke_start 110 30 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u tests/smoke/init.lua
smoke_keys ' ss'
smoke_expect 'Save session for work' || rc=1
smoke_expect '│\.vim' || rc=1                 # the suffix shows even with nothing typed
smoke_expect '5 saved for work' || rc=1
smoke_expect 'type a name' || rc=1
smoke_type co
smoke_expect '│co\.vim' || rc=1
smoke_expect '3 of 5 saved' || rc=1
smoke_expect 'new session' || rc=1
smoke_keys Tab; smoke_keys Tab
smoke_expect '│cooli\.vim' || rc=1
smoke_expect '▌ cooli ' || rc=1
smoke_expect 'overwrites cooli\.vim' || rc=1
smoke_expect '3 of 5 saved' || rc=1           # Tab did not narrow the list
smoke_keys Enter
smoke_expect 'Overwrite session\?' || rc=1
smoke_keys o
smoke_expect 'Saved .*cooli\.vim' || rc=1
smoke_expect 'Reload with :SessionMgr load cooli  or  <leader>sl' || rc=1
smoke_reject 'Press ENTER' || rc=1
smoke_keys ' ss'
smoke_expect '│cooli\.vim' || rc=1            # pre-filled with the active session
smoke_keys C-u; smoke_type 'brand new'; smoke_keys Enter
smoke_expect 'Saved .*brand new\.vim' || rc=1
smoke_reject 'Overwrite' || rc=1
smoke_keys ' sS'
smoke_expect 'Saved .*default\.vim' || rc=1   # save! never asks
smoke_expect ':SessionMgr load!' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_stop; rm -rf "$SMOKE_ROOT"
exit $rc
