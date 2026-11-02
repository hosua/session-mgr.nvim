#!/usr/bin/env bash
# Live check (real config, throwaway sessions dir, never run in CI): quitting
# writes autosave.vim, a plain `nvim` autoloads it with the hint message,
# <leader>sn starts a new empty session, and `nvim file` does not autoload.
# Also covers <leader>sL with no autosave and no default session.
set -uo pipefail
export LIVE_ISOLATE="sessions"
# shellcheck source=/dev/null
source "${LIVE_LIB:-${HOME}/.config/nvim/.claude/skills/nvim-create-and-integrate-plugin/scripts/live_lib.sh}"
rc=0

live_setup
echo alpha >a.txt
echo bravo >b.txt

echo "-- <leader>sL with nothing saved"
live_nvim 140 32 a.txt
smoke_type ' sL'
smoke_expect 'No "autosave" or "default" session for' || rc=1
smoke_keys ':qa!' Enter
sleep 1
rm -rf "${LIVE_TMP}"/data/nvim/sessions

echo "-- run 1: nvim a.txt, quit (exit save)"
live_nvim 140 32 a.txt
smoke_reject 'automatically loaded' || rc=1
smoke_keys ':qa!' Enter
sleep 1
if compgen -G "${LIVE_TMP}/data/nvim/sessions/*/autosave.vim" >/dev/null; then
    echo "  ok    exit wrote autosave.vim"
else
    echo "  FAIL  no autosave.vim after exit"
    rc=1
fi

echo "-- run 2: plain nvim autoloads, then <leader>sn"
live_nvim 140 32
sleep 1
smoke_expect 'Last autosaved session was automatically loaded' || rc=1
smoke_expect 'start a new session with <leader>sn' || rc=1
smoke_expect 'alpha' || rc=1
smoke_reject 'Loaded autosave' || rc=1
smoke_type ' sn'
smoke_expect 'New session: nothing open. Save it with <leader>ss' || rc=1
smoke_reject 'alpha' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys ':qa!' Enter
sleep 1

echo "-- run 3: nvim b.txt must not autoload"
live_nvim 140 32 b.txt
sleep 1
smoke_expect 'bravo' || rc=1
smoke_reject 'automatically loaded' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys ':qa!' Enter
sleep 1

live_teardown
exit "${rc}"
