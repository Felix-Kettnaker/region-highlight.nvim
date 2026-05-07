local M = {}

--- Extract the human-readable label from a #region line.
--- Strips the comment prefix, the #region keyword, and the optional "fold" keyword.
---@param line string raw buffer line
---@return string label (may be empty for unlabelled regions)
local function region_label(line)
  local after = line:match("#region(.*)") or ""
  after = vim.trim(after)
  -- Remove standalone "fold" keyword (e.g. "#region fold" or "#region fold MyName")
  after = after:gsub("^fold%s*", "")
  return vim.trim(after)
end

--- Open a snacks.nvim picker listing all #region entries in bufnr (default: current buffer).
--- Uses the already-parsed region data so only real comment-line markers are shown.
---@param bufnr integer|nil
function M.buf(bufnr)
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.notify(
      "region-highlight: snacks.nvim (with picker) is required for the region picker",
      vim.log.levels.WARN
    )
    return
  end

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local region_list = vim.b[bufnr].region_list
  if not region_list or #region_list == 0 then
    vim.notify("region-highlight: no regions in this buffer", vim.log.levels.INFO)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local sorted = vim.deepcopy(region_list)
  table.sort(sorted, function(a, b) return a.start_line < b.start_line end)

  local items = {}
  for _, region in ipairs(sorted) do
    local src_line = lines[region.start_line + 1] or ""
    local label = region_label(src_line)
    local display = label ~= "" and label or ("region " .. region.encounter_index)
    table.insert(items, {
      text = display,
      label = label,
      region = region,
      file = filepath ~= "" and filepath or nil,
      pos = { region.start_line + 1, 1 },
    })
  end

  local win = vim.api.nvim_get_current_win()

  snacks.picker {
    title = "Regions (buffer)",
    items = items,
    preview = filepath ~= "" and "file" or nil,
    format = function(item, _)
      local indent = string.rep("  ", item.region.depth - 1)
      local name = item.label ~= "" and item.label or ("(unnamed " .. item.region.encounter_index .. ")")
      local range = string.format(" L%d–%d", item.region.start_line + 1, item.region.end_line + 1)
      return {
        { indent .. name, "SnacksPickerLabel" },
        { range, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_cursor(win, { item.region.start_line + 1, 0 })
        vim.cmd("normal! zv")
      end
    end,
  }
end

--- Open a snacks.nvim picker scanning the entire project for #region markers via rg.
--- Shows all #region occurrences across all project files with file preview.
function M.global()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.notify(
      "region-highlight: snacks.nvim (with picker) is required for the region picker",
      vim.log.levels.WARN
    )
    return
  end

  if vim.fn.executable("rg") == 0 then
    vim.notify("region-highlight: ripgrep (rg) is required for the global region picker", vim.log.levels.WARN)
    return
  end

  local cwd = vim.fn.getcwd()
  -- rg outputs "filepath:linenum:content"; #region never appears in #endregion so no extra filter needed
  local raw = vim.fn.systemlist(
    "rg --line-number --no-heading --color=never --fixed-strings '#region' " .. vim.fn.shellescape(cwd)
  )

  if not raw or #raw == 0 then
    vim.notify("region-highlight: no #region markers found in project", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, rg_line in ipairs(raw) do
    -- Parse "filepath:linenum:content" — filepath may contain colons, linenum is all-digits
    local filepath, lnum_str, content = rg_line:match("^(.+):(%d+):(.*)$")
    if filepath and lnum_str then
      local lnum = tonumber(lnum_str)
      local label = region_label(content)
      local rel = vim.fn.fnamemodify(filepath, ":.")
      table.insert(items, {
        text = (label ~= "" and label or rel) .. " " .. rel,
        label = label,
        lnum = lnum,
        file = filepath,
        pos = { lnum, 1 },
      })
    end
  end

  if #items == 0 then
    vim.notify("region-highlight: no #region markers found in project", vim.log.levels.INFO)
    return
  end

  snacks.picker {
    title = "Regions (project)",
    items = items,
    preview = "file",
    format = function(item, _)
      local name = item.label ~= "" and item.label or "(unnamed)"
      local loc = string.format(" %s:%d", vim.fn.fnamemodify(item.file, ":."), item.lnum)
      return {
        { name, "SnacksPickerLabel" },
        { loc, "Comment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
        vim.cmd("normal! zv")
      end
    end,
  }
end

return M

