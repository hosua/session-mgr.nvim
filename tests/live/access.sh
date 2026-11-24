#!/usr/bin/env bash
# Live check (real config, throwaway sessions dir, never run in CI): the
# no-access approval question. /etc/gitea (root:gitea 755) and / ask with the
# right reason and the root/sudo warning, n writes nothing, y approves that
# directory (not home) and the next save is silent. chmod 555 and 111 dirs
# under a fake $HOME ask. project.require_access = false skips the question.
# A git root or .session-root inside an unwritable directory never asks.
# Needs a normal user (root passes every access check) and a root:gitea
# /etc/gitea.
set -uo pipefail
export LIVE_ISOLATE="sessions"
REAL_HOME=${HOME}
# shellcheck source=/dev/null
source "${LIVE_LIB:-${HOME}/.config/nvim/.claude/skills/nvim-create-and-integrate-plugin/scripts/live_lib.sh}"
rc=0
[ "$(id -u)" = 0 ] && { echo "skip: running as root"; exit 0; }

live_setup
export XDG_CONFIG_HOME="${REAL_HOME}/.config" XDG_CACHE_HOME="${REAL_HOME}/.cache"
SESS="${LIVE_TMP}/data/nvim/sessions"
roots() { find "${SESS}" -name approved_roots.json -exec cat {} + 2>/dev/null; }
files() { find "${SESS}" -type f 2>/dev/null | sort; }
reset() { find "${SESS}" -name approved_roots.json -delete 2>/dev/null; }
no() { smoke_reject 'E[0-9]+:' || rc=1; smoke_reject 'INSERT' || rc=1; }

ask_case() { # dir file reason-regex
    local dir=$1 file=$2 reason=$3
    echo "-- ${dir}: <leader>ss then n"
    reset
    cd "${dir}" || return
    local key="${SESS}/$(printf '%s' "${dir}" | tr / %)"
    rm -rf "${key}"
    live_nvim 140 32 "${file}"
    smoke_type ' ss'
    sleep 1
    smoke_expect 'Create a session for' || rc=1
    smoke_expect "${reason}" || rc=1
    smoke_expect 'root and sudo' || rc=1
    smoke_keys n
    sleep 1
    no
    [ -z "$(roots)" ] && [ ! -e "${key}" ] && echo "  ok    n wrote nothing" || { echo "  FAIL  n wrote: $(roots) $(ls "${key}" 2>&1)"; rc=1; }
    echo "-- ${dir}: :SessionMgr save foo then y"
    smoke_type ':SessionMgr save foo'
    smoke_keys Enter
    sleep 1
    smoke_expect 'Create a session for' || rc=1
    smoke_keys y
    sleep 1
    no
    if roots | grep -q "\"${dir}\""; then echo "  ok    ${dir} approved"; else echo "  FAIL  approved_roots: $(roots)"; rc=1; fi
    if roots | grep -q "\"${FAKE_HOME_RE:-NOHOME}\""; then echo "  FAIL  home approved"; rc=1; fi
    smoke_type ':SessionMgr save bar'
    smoke_keys Enter
    sleep 1
    smoke_reject 'Create a session for' || rc=1
    no
    smoke_keys ':qa!' Enter
    sleep 1
}

echo this >"${LIVE_TMP}/f.txt"
# real HOME here: /etc/gitea and / are not under it
cp "${LIVE_TMP}/f.txt" "${LIVE_TMP}/gitea.txt"
ask_case /etc/gitea "${LIVE_TMP}/gitea.txt" 'no write access.*owner root, group gitea'
ask_case / "${LIVE_TMP}/gitea.txt" 'parent of your home'

FAKE="${LIVE_TMP}/h/u"
mkdir -p "${FAKE}/d555" "${FAKE}/d000"
export HOME="${FAKE}"
chmod 555 "${FAKE}/d555"
ask_case "${FAKE}/d555" "${LIVE_TMP}/gitea.txt" 'no write access'
chmod 111 "${FAKE}/d000"
ask_case "${FAKE}/d000" "${LIVE_TMP}/gitea.txt" 'no read or write access'
chmod 755 "${FAKE}/d000" "${FAKE}/d555"
export HOME="${REAL_HOME}"

echo "-- require_access = false: /etc/gitea falls back to home, no prompt"
reset
cd /etc/gitea || exit 1
live_nvim 140 32 "${LIVE_TMP}/gitea.txt"
smoke_type ":lua require('session-mgr').setup({project={require_access=false}})"
smoke_keys Enter
smoke_type ':SessionMgr save baz'
smoke_keys Enter
sleep 1
smoke_reject 'Create a session for' || rc=1
no
[ -z "$(roots)" ] && echo "  ok    no approval written" || { echo "  FAIL  $(roots)"; rc=1; }
smoke_keys ':qa!' Enter
sleep 1

echo "-- git root and marker inside an unwritable dir never ask"
export HOME="${FAKE}"
mkdir -p "${FAKE}/ro/git" "${FAKE}/ro/mark"
git -C "${FAKE}/ro/git" init -q
: >"${FAKE}/ro/mark/.session-root"
chmod 555 "${FAKE}/ro/git" "${FAKE}/ro/mark" "${FAKE}/ro"
for d in ro/git ro/mark; do
    reset
    cd "${FAKE}/${d}" || exit 1
    live_nvim 140 32 "${LIVE_TMP}/gitea.txt"
    smoke_type ':SessionMgr save q'
    smoke_keys Enter
    sleep 1
    smoke_reject 'Create a session for' || rc=1
    no
    smoke_keys ':qa!' Enter
    sleep 1
done

echo "-- exit autosave in a pending dir asks nothing, writes nothing"
reset
cd /etc/gitea || exit 1
rm -rf "${SESS}/%etc%gitea"
live_nvim 140 32 "${LIVE_TMP}/gitea.txt"
smoke_keys ':qa' Enter
sleep 1
smoke_screen | grep -q 'Create a session for' && { echo "  FAIL  asked on exit"; rc=1; }
[ ! -e "${SESS}/%etc%gitea" ] && [ -z "$(roots)" ] && echo "  ok    nothing written" || { echo "  FAIL  $(files)"; rc=1; }
smoke_stop

chmod 755 "${FAKE}/ro" "${FAKE}/ro/git" "${FAKE}/ro/mark"
export HOME="${REAL_HOME}"
live_teardown
exit "${rc}"
