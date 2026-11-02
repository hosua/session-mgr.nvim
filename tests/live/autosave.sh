#!/usr/bin/env bash
# Live check (real config, throwaway sessions dir, never run in CI): the
# autosave timer, <leader>sa, the picker footer toggle (s), <leader>sA, and
# the timer writing autosave.vim. Also covers <leader>sL choosing autosave
# or default.
set -uo pipefail
export LIVE_ISOLATE="sessions"
# shellcheck source=/dev/null
source "${LIVE_LIB:-${HOME}/.config/nvim/.claude/skills/nvim-create-and-integrate-plugin/scripts/live_lib.sh}"
rc=0
TIMER_PRINT=':lua print("timer=" .. tostring(require("session-mgr.autosave").running()))'

live_setup
echo hello >a.txt
live_nvim 140 32 a.txt
smoke_expect 'hello' || rc=1

echo "-- autosave timer and <leader>sa"
smoke_keys "${TIMER_PRINT}" Enter
smoke_expect 'timer=true' || rc=1
smoke_type ' sa'
smoke_expect 'Autosave off' || rc=1
smoke_keys "${TIMER_PRINT}" Enter
smoke_expect 'timer=false' || rc=1
smoke_type ' sa'
smoke_expect 'Autosave on: autosave.vim every 5m, on exit and before a load' || rc=1

echo "-- picker footer and s toggle"
sleep 3
smoke_type ' sl'
smoke_expect 'Load a session for' || rc=1
smoke_expect 'a all  s autosave on' || rc=1
smoke_keys s
smoke_expect 's autosave off' || rc=1
smoke_reject 'Autosave off' || rc=1
smoke_keys s
smoke_expect 's autosave on' || rc=1
smoke_keys q

echo "-- <leader>sA"
smoke_type ' sA'
smoke_expect 'Showing your saved sessions for all projects' || rc=1
smoke_keys q

echo "-- timer writes autosave.vim"
smoke_keys ':lua require("session-mgr.autosave").start(1000)' Enter
sleep 2
if compgen -G "${LIVE_TMP}/data/nvim/sessions/*/autosave.vim" >/dev/null; then
    echo "  ok    timer wrote autosave.vim"
else
    echo "  FAIL  no autosave.vim under the throwaway sessions dir"
    rc=1
fi

echo "-- <leader>sL: autosave, then default"
smoke_keys ':lua require("session-mgr.autosave").start(300000)' Enter
smoke_type ' sS'
smoke_expect 'Reload with :SessionMgr load default' || rc=1
echo bravo >b.txt
echo charlie >c.txt
smoke_keys ':e b.txt | lua require("session-mgr.session").autosave()' Enter
smoke_keys ':e c.txt' Enter
smoke_type ' sL'
smoke_expect 'Loaded autosave' || rc=1
smoke_expect 'bravo' || rc=1
smoke_type ' sa'
smoke_expect 'Autosave off' || rc=1
smoke_type ' sL'
smoke_expect 'Loaded default' || rc=1
smoke_expect 'hello' || rc=1

smoke_reject 'E[0-9]+:' || rc=1
smoke_reject 'INSERT' || rc=1
smoke_keys ':qa!' Enter
sleep 1
live_teardown
exit "${rc}"
