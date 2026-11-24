#!/usr/bin/env bash
# Live check (real config, throwaway sessions dir, never run in CI): quitting
# writes autosave.vim; a plain `nvim` asks y/N before loading it (y loads and
# shows the hint, Enter leaves nvim empty); <leader>sn starts a new empty
# session; `nvim file` does not ask; `nvim .git/COMMIT_EDITMSG` (what
# `git commit` runs) neither asks nor touches autosave.vim. Also covers
# <leader>sL with no autosave and no default session.
set -uo pipefail
export LIVE_ISOLATE="sessions"
# shellcheck source=/dev/null
source "${LIVE_LIB:-${HOME}/.config/nvim/.claude/skills/nvim-create-and-integrate-plugin/scripts/live_lib.sh}"
rc=0

live_setup
git init -q "${LIVE_PROJ}"
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

echo "-- run 2: plain nvim asks; y loads, then <leader>sn"
live_nvim 140 32
sleep 1
smoke_expect 'Load your last autosaved session' || rc=1
smoke_expect 'Why +git root' || rc=1
smoke_expect 'Session +autosave.vim' || rc=1
smoke_expect 'Saved +' || rc=1
smoke_reject 'alpha' || rc=1
smoke_keys y
sleep 1
smoke_expect 'Loaded autosave \(git root ' || rc=1
smoke_expect 'start a new session with <leader>sn' || rc=1
smoke_expect 'alpha' || rc=1
smoke_type ' sn'
smoke_expect 'New session: nothing open. Save it with <leader>ss' || rc=1
smoke_reject 'alpha' || rc=1
smoke_reject 'E[0-9]+:' || rc=1
smoke_keys ':qa!' Enter
sleep 1

echo "-- run 2b: plain nvim asks; Enter (the default) leaves nvim empty"
live_nvim 140 32
sleep 1
smoke_expect 'Load your last autosaved session' || rc=1
smoke_keys Enter
sleep 1
smoke_expect 'Autosave not loaded. Load it later with <leader>sL' || rc=1
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

echo "-- run 4: nvim .git/COMMIT_EDITMSG (as git commit does) neither asks nor writes autosave.vim"
before=$(sha256sum "${LIVE_TMP}"/data/nvim/sessions/*/autosave.vim)
echo "fix: something" >.git/COMMIT_EDITMSG
live_nvim 140 32 .git/COMMIT_EDITMSG
sleep 1
smoke_reject 'Load your last autosaved session' || rc=1
smoke_keys ':qa!' Enter
sleep 1
after=$(sha256sum "${LIVE_TMP}"/data/nvim/sessions/*/autosave.vim)
if [ "${before}" = "${after}" ]; then
    echo "  ok    autosave.vim untouched by a COMMIT_EDITMSG run"
else
    echo "  FAIL  autosave.vim changed after a COMMIT_EDITMSG run"
    rc=1
fi

live_teardown
exit "${rc}"
