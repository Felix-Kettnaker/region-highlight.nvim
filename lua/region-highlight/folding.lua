local M = {}

-- Module-level storage for fold data, keyed by bufnr.
-- Avoids vim.b msgpack serialization which converts sparse numeric-keyed tables
-- into arrays padded with vim.NIL (a truthy value that breaks foldexpr checks).
local _fold_data = {}

--- Called by vim's foldexpr for each line
---@param lnum integer 1-indexed line number
---@return string fold expression result
function M.foldexpr(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local fd = _fold_data[bufnr]
  if not fd then
    return "0"
  end

  if fd.starts[lnum] then
    return ">" .. fd.starts[lnum]
  end

  return tostring(fd.levels[lnum] or 0)
end

--- Build and install fold data for a buffer
---@param bufnr integer
---@param regions table[]
function M.setup_folds(bufnr, regions)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local starts = {} -- lnum (1-indexed) -> depth: this lnum starts a fold of this depth
  local levels = {} -- lnum (1-indexed) -> current fold level

  -- Initialize all lines to level 0
  for lnum = 1, total_lines do
    levels[lnum] = 0
  end

  -- Sort by depth ascending so inner regions override outer levels
  local sorted = vim.deepcopy(regions)
  table.sort(sorted, function(a, b) return a.depth < b.depth end)

  for _, region in ipairs(sorted) do
    -- start_line and end_line are 0-indexed; lnum is 1-indexed
    for row = region.start_line, region.end_line do
      local lnum = row + 1
      levels[lnum] = math.max(levels[lnum] or 0, region.depth)
    end
    starts[region.start_line + 1] = region.depth
  end

  _fold_data[bufnr] = { starts = starts, levels = levels }
end

--- Release fold data for a buffer (call on BufDelete)
---@param bufnr integer
function M.clear_folds(bufnr)
  _fold_data[bufnr] = nil
end

--- Return fold data for a buffer (for debugging/inspection)
---@param bufnr integer
---@return table|nil
function M.get_fold_data(bufnr)
  return _fold_data[bufnr]
end

--- Set fold options on the current window. Must be called from a window context.
--- Call this from BufWinEnter or BufEnter autocmds.
function M.install_fold_options()
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "v:lua.require('region-highlight.folding').foldexpr(v:lnum)"
  vim.wo.foldenable = true
end

--- Close folds for regions that have fold_on_load = true.
--- Must be called from BufWinEnter (window context required).
---@param bufnr integer
---@param regions table[]
---@param opts table
function M.apply_initial_folds(bufnr, regions, opts)
  -- Only run once per buffer load
  if vim.b[bufnr].region_initial_fold_done then
    return
  end

  local to_fold = {}
  for _, region in ipairs(regions) do
    if opts.fold_all or region.fold_on_load then
      table.insert(to_fold, region)
    end
  end

  if #to_fold == 0 then
    vim.b[bufnr].region_initial_fold_done = true
    return
  end

  -- Sort descending by depth so inner folds are closed before outer
  table.sort(to_fold, function(a, b) return a.depth > b.depth end)

  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return
  end

  local saved_cursor = vim.api.nvim_win_get_cursor(win)
  for _, region in ipairs(to_fold) do
    local lnum = region.start_line + 1
    pcall(vim.api.nvim_win_set_cursor, win, { lnum, 0 })
    pcall(vim.cmd, "normal! zc")
  end
  pcall(vim.api.nvim_win_set_cursor, win, saved_cursor)

  -- Set AFTER all folds are applied
  vim.b[bufnr].region_initial_fold_done = true
end

return M
