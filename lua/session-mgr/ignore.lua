--- Buffers that must never decide anything about a session: the message
--- editors git, hg and cron open (`git commit` runs nvim on COMMIT_EDITMSG),
--- and anything inside a .git directory. Configured by `ignore`.
local M = {}

--- Pure: does this file name or filetype match the ignore lists?
--- @param name string full buffer name, "" when unnamed
--- @param filetype string
--- @param cfg { filetypes: string[], patterns: string[] }
--- @return boolean
function M.matches(name, filetype, cfg)
  if filetype ~= "" and vim.tbl_contains(cfg.filetypes, filetype) then
    return true
  end
  if name ~= "" then
    for _, pat in ipairs(cfg.patterns) do
      if name:find(pat) then
        return true
      end
    end
  end
  return false
end

--- @param bufnr integer|nil defaults to the current buffer
--- @param cfg { filetypes: string[], patterns: string[] }|nil defaults to the `ignore` config
--- @return boolean
function M.is_ignored(bufnr, cfg)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  cfg = cfg or require("session-mgr.config").get().ignore
  return M.matches(vim.api.nvim_buf_get_name(bufnr), vim.bo[bufnr].filetype, cfg)
end

--- True when some listed buffer is ignored.
--- @return boolean
function M.any_open()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted and M.is_ignored(buf) then
      return true
    end
  end
  return false
end

return M
