# session-mgr.nvim

Named, per-project Neovim sessions with a fast floating picker: save, load, rename, delete, sort and filter sessions, with use counts and timestamps.

## Install

Private repo: lazy.nvim loads the local checkout, and only clones from
GitHub (which needs `gh auth setup-git`) when the checkout is missing.

```lua
-- lua/configs/lazy.lua
dev = { path = "~/dev", fallback = true },

-- lua/plugins/session-mgr.lua
return { { "hosua/session-mgr.nvim", dev = true, cmd = { "SessionMgr" }, opts = {} } }
```

## Commands

| Command | What it does |
|---|---|

## Default keymaps

None are installed unless `keymaps = true`. Suggested:

| Key | Command |
|---|---|

## Configuration

Every option, with its default:

```lua
require("session-mgr").setup {
  notify = true,
}
```

## Health

`:checkhealth session-mgr`

## Development

```bash
make test         # headless unit tests, no dependencies
make integration  # against a throwaway XDG tree
make check        # stylua --check
```
