<!-- nvim-plugin-workflow:start -->
# Plugin workflow (shared by every plugin made from ~/.config/nvim)

This block is copied in by `sync_workflow.sh` from
`~/.config/nvim/.claude/skills/nvim-create-and-integrate-plugin/`. Edit it
there and re-sync; a local edit is overwritten and `gates.sh` reports drift.

## Who does what

The main session orchestrates and is the only one that talks to you. It
dispatches:

- `nvim-plugin-builder` (Sonnet): creates the repo or changes the plugin and
  its config-repo wiring, commits on a `feature/` or `fix/` branch, pushes,
  opens the PR. It never merges.
- `nvim-plugin-tester` (Sonnet): runs the gates, CI, the live check with the
  real config, records README media with vhs, and returns PASS or FAIL with
  the fixes needed. It changes no feature code.
- `doc-writer`: README and other docs, from the tester's capture list.

## The loop

1. The main session settles the behaviour with you (questions, plan) and
   dispatches the builder with the repo, the branch and the spec.
2. The tester verifies the branch. On FAIL the main session sends its
   findings to the builder, and the tester runs again.
3. On PASS the doc-writer updates the README using the images the tester
   listed in `docs/media/CAPTURES.md`.
4. The main session reruns `scripts/gates.sh` (the README is checked by a
   spec), pushes, waits for CI, and merges without asking: plugin PR first,
   then the config PR. A tester PASS is the approval.
5. After merging: `git switch main && git pull --ff-only` in both repos.

Anything the tester could not check (mouse, colours, Neovide, feel) is
listed in the final report to you, not silently skipped.

## Scripts

All under `~/.config/nvim/.claude/skills/nvim-create-and-integrate-plugin/scripts/`:

- `gates.sh [--live] <repo>`: workflow sync, `make test`, `make integration`,
  `make smoke`, `stylua --check`, secrets sweep. Prints one line per gate.
- `live_lib.sh`: sourced by `tests/live/*.sh` to run the real config in tmux
  against a throwaway data dir. `LIVE_ISOLATE` names the data dirs the
  plugin writes, so your real ones are never touched.
- `sync_workflow.sh <repo>`: copies the agents and this block.
- `secrets_sweep.sh`, `preflight.sh`, `scaffold.sh`: as in the skill.

## Rules that do not bend

- Branches are `feature/<slug>` or `fix/<slug>`; no worktrees, no stash.
- Never test against real user data: integration runs under a throwaway XDG
  tree, live checks isolate the plugin's own data dirs.
- Repo visibility is always given by you; a builder never guesses it.
- Commit messages and PR text follow the humanize rules: the concrete change
  in the subject, why in the body, what was run and seen in the test plan.
<!-- nvim-plugin-workflow:end -->
