#!/usr/bin/env bash
# Drive a real nvim TUI inside a detached tmux server and read the screen
# back, for UI that headless mode cannot render (floats, extmarks, footers).
#
#   source tmux_smoke.sh               # then use the functions below
#   smoke_start 120 40 nvim --clean -u tests/smoke/init.lua
#   smoke_keys ':SessionMgr load' Enter
#   smoke_expect 'Load a session for'  # grep -E against the captured screen
#   smoke_reject 'E[0-9]+:'            # fail if an error is on screen
#   smoke_resize 80 24
#   smoke_screen                       # print the screen (for debugging)
#   smoke_stop
#
# Uses its own tmux socket (-L), so it never touches the user's tmux server.
# Not covered: mouse hover/click and colours. Those go to the human checkpoint.
SMOKE_SOCK=${SMOKE_SOCK:-nvim-smoke-$$}
SMOKE_WAIT=${SMOKE_WAIT:-0.4}

smoke_start() {
  local w=$1 h=$2; shift 2
  tmux -L "$SMOKE_SOCK" kill-server 2>/dev/null || true
  tmux -L "$SMOKE_SOCK" -f /dev/null new-session -d -x "$w" -y "$h" "$@"
  trap smoke_stop EXIT
  sleep 1
}
smoke_keys() { tmux -L "$SMOKE_SOCK" send-keys "$@"; sleep "$SMOKE_WAIT"; }
smoke_type() { tmux -L "$SMOKE_SOCK" send-keys -l "$1"; sleep "$SMOKE_WAIT"; }
smoke_resize() { tmux -L "$SMOKE_SOCK" resize-window -x "$1" -y "$2"; sleep "$SMOKE_WAIT"; }
smoke_screen() { tmux -L "$SMOKE_SOCK" capture-pane -p; }
smoke_expect() {
  if smoke_screen | grep -qE -- "$1"; then echo "  ok    expect /$1/"; return 0; fi
  echo "  FAIL  expected /$1/ on screen:"; smoke_screen | sed 's/^/        |/'; return 1
}
smoke_reject() {
  if smoke_screen | grep -qE -- "$1"; then
    echo "  FAIL  /$1/ should not be on screen:"; smoke_screen | sed 's/^/        |/'; return 1
  fi
  echo "  ok    reject /$1/"
}
smoke_stop() { tmux -L "$SMOKE_SOCK" kill-server 2>/dev/null || true; trap - EXIT; }
