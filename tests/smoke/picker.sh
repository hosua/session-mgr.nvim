#!/usr/bin/env bash
# Screen-level smoke test of the picker in a real TUI (tmux). Text only:
# colours, hover and clicks are checked by a human.
set -euo pipefail
cd "$(dirname "$0")/../.."
source tests/smoke/lib.sh
SMOKE_ROOT=$(mktemp -d); export SMOKE_ROOT
mkdir -p "$SMOKE_ROOT/work"; echo hi >"$SMOKE_ROOT/work/a.txt"
rc=0
smoke_start 130 32 env SMOKE_ROOT="$SMOKE_ROOT" nvim --clean -u tests/smoke/init.lua
smoke_keys ' sl'
smoke_expect 'Load a session for' || rc=1
smoke_expect '▌ +1 +default' || rc=1
smoke_expect 'not a git repo: listed only from this folder \(<leader>sa' || rc=1
smoke_expect '⏎ load  / filter' || rc=1
smoke_keys 2
smoke_expect 'Uses ▼' || rc=1
smoke_keys a
smoke_expect 'Showing your saved sessions for all projects' || rc=1
smoke_expect 'other-repo +/srv/other-repo' || rc=1
smoke_keys /; smoke_type coo
smoke_expect '/ coo' || rc=1
smoke_expect '4 of 7' || rc=1
smoke_expect 'cool  other-repo' || rc=1
smoke_expect '⏎ keep  esc clear' || rc=1
smoke_keys Enter; smoke_keys d
smoke_expect 'Delete session\?' || rc=1
smoke_keys q; smoke_keys '?'
smoke_expect 'session-mgr keys' || rc=1
smoke_keys q
smoke_resize 80 24
smoke_expect 'Showing your saved sessions' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys C-l; smoke_keys a; smoke_keys j; smoke_keys Enter
smoke_expect 'Loaded abc' || rc=1
smoke_reject 'Load a session for' || rc=1
smoke_stop; rm -rf "$SMOKE_ROOT"
exit $rc
