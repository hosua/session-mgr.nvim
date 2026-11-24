#!/usr/bin/env bash
# Live check (real config, throwaway sessions dir, never run in CI): the
# startup question answers n, Esc and q all leave nvim empty with the toast;
# a .session-root file makes a project; a non-git dir under home resolves to
# home; in a parent of (a fake) $HOME, :SessionMgr save asks "Create a session
# for ... ?" with the root/sudo warning and y writes approved_roots.json, and
# the exit autosave in an unapproved parent asks nothing and writes nothing; a
# read-only directory (chmod 555, so run this as a normal user: root passes
# every access check) asks too, says "no write access", and y approves that
# directory itself, not home.
set -uo pipefail
export LIVE_ISOLATE="sessions"
REAL_HOME=${HOME}
# shellcheck source=/dev/null
source "${LIVE_LIB:-${HOME}/.config/nvim/.claude/skills/nvim-create-and-integrate-plugin/scripts/live_lib.sh}"
rc=0

live_setup
# Fake $HOME inside the throwaway dir; the real config and caches stay reachable.
export XDG_CONFIG_HOME="${REAL_HOME}/.config" XDG_CACHE_HOME="${REAL_HOME}/.cache"
FAKE="${LIVE_TMP}/h/u"
mkdir -p "${FAKE}/plain" "${FAKE}/mark/sub"
export HOME="${FAKE}"
echo one >"${FAKE}/mark/a.txt"
: >"${FAKE}/mark/.session-root"
echo two >"${FAKE}/plain/b.txt"

echo "-- marker project: save by exit, then n / Esc / q"
cd "${FAKE}/mark/sub" || exit 1
live_nvim 140 32 ../a.txt
smoke_keys ':qa!' Enter
sleep 1
for k in n Escape q; do
    echo "-- answer ${k}"
    live_nvim 140 32
    sleep 1
    smoke_expect 'Load your last autosaved session' || rc=1
    smoke_expect 'Why +marker \.session-root' || rc=1
    smoke_expect 'Project +~/mark' || rc=1
    smoke_keys "${k}"
    sleep 1
    smoke_expect 'Autosave not loaded. Load it later with' || rc=1
    smoke_reject 'one' || rc=1
    smoke_reject 'E[0-9]+:' || rc=1
    smoke_keys ':qa!' Enter
    sleep 1
done

echo "-- plain dir under home resolves to home"
cd "${FAKE}/plain" || exit 1
live_nvim 140 32 b.txt
smoke_keys ':qa!' Enter
sleep 1
live_nvim 140 32
sleep 1
smoke_expect 'Why +home' || rc=1
smoke_expect 'Project +~ ' || rc=1
smoke_keys n
smoke_keys ':qa!' Enter
sleep 1

echo "-- parent of home: exit autosave asks nothing and writes nothing"
PARENT="${LIVE_TMP}/h"
cd "${PARENT}" || exit 1
echo three >c.txt
before=$(find "${LIVE_TMP}/data/nvim/sessions" -type f | sort)
live_nvim 140 32 c.txt
smoke_reject 'Create a session for' || rc=1
smoke_keys ':qa!' Enter
sleep 1
after=$(find "${LIVE_TMP}/data/nvim/sessions" -type f | sort)
[ "${before}" = "${after}" ] && echo "  ok    nothing written" || { echo "  FAIL  files appeared: ${after}"; rc=1; }

echo "-- parent of home: :SessionMgr save asks, n writes nothing, y writes approved_roots.json"
live_nvim 140 32 c.txt
smoke_type ':SessionMgr save'
smoke_keys Enter
sleep 1
smoke_expect 'Create a session for' || rc=1
smoke_expect 'parent of your home' || rc=1
smoke_expect 'root and sudo' || rc=1
smoke_keys n
sleep 1
smoke_reject 'E[0-9]+:' || rc=1
if find "${LIVE_TMP}/data/nvim/sessions" -name approved_roots.json | grep -q .; then
    echo "  FAIL  approved_roots.json after n"
    rc=1
fi
smoke_type ':SessionMgr save'
smoke_keys Enter
sleep 1
smoke_expect 'Create a session for' || rc=1
smoke_keys y
sleep 1
smoke_reject 'E[0-9]+:' || rc=1
if find "${LIVE_TMP}/data/nvim/sessions" -name approved_roots.json | grep -q .; then
    echo "  ok    approved_roots.json written after y"
else
    echo "  FAIL  no approved_roots.json after y"
    rc=1
fi
smoke_keys ':qa!' Enter
sleep 1

echo "-- read-only directory: asks with the reason, y approves the directory"
if [ "$(id -u)" = 0 ]; then
    echo "  skip  running as root, every access check passes"
else
    RO="${FAKE}/readonly"
    mkdir -p "${RO}"
    echo four >"${RO}/d.txt"
    chmod 555 "${RO}"
    cd "${RO}" || exit 1
    before=$(find "${LIVE_TMP}/data/nvim/sessions" -name approved_roots.json -exec cat {} +)
    live_nvim 140 32 d.txt
    smoke_type ':SessionMgr save'
    smoke_keys Enter
    sleep 1
    smoke_expect 'Create a session for' || rc=1
    smoke_expect 'no write access to' || rc=1
    smoke_expect 'root and sudo' || rc=1
    smoke_keys n
    sleep 1
    smoke_reject 'E[0-9]+:' || rc=1
    smoke_type ':SessionMgr save'
    smoke_keys Enter
    sleep 1
    smoke_keys y
    sleep 1
    smoke_reject 'E[0-9]+:' || rc=1
    smoke_expect 'approved directory' || rc=1
    if find "${LIVE_TMP}/data/nvim/sessions" -name approved_roots.json -exec cat {} + | grep -q "${RO}"; then
        echo "  ok    ${RO} approved, not home"
    else
        echo "  FAIL  ${RO} missing from approved_roots.json (before: ${before})"
        rc=1
    fi
    smoke_keys ':qa!' Enter
    sleep 1
    chmod 755 "${RO}"
fi

export HOME="${REAL_HOME}"
live_teardown
exit "${rc}"
