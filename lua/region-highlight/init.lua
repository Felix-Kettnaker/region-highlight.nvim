local config = require("region-highlight.config")
local regions_mod = require("region-highlight.regions")
local highlights = require("region-highlight.highlights")
local folding = require("region-highlight.folding")

local M = {}

-- Debounce timer per buffer
local timers = {}

--- Process a buffer: parse regions, apply highlights, set up folds
---@param bufnr integer
---@param initial_load boolean whether this is the first time the buffer is loaded
local function process_buffer(bufnr, initial_load)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  if ft == "" then
    return
  end

  local regions = regions_mod.parse(bufnr)

  highlights.apply(bufnr, regions, config.options)
  folding.setup_folds(bufnr, regions)

  -- Store regions for later use (e.g., initial fold application)
  vim.b[bufnr].region_list = regions

  if initial_load then
    -- Schedule fold application for after BufWinEnter gives us a window
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        folding.apply_initial_folds(bufnr, regions, config.options)
      end
    end)
  end
end

--- Debounced re-process after text change
---@param bufnr integer
local function schedule_refresh(bufnr)
  if timers[bufnr] then
    timers[bufnr]:stop()
    timers[bufnr]:close()
    timers[bufnr] = nil
  end

  local timer = vim.uv.new_timer()
  timers[bufnr] = timer
  timer:start(300, 0, vim.schedule_wrap(function()
    timers[bufnr] = nil
    if vim.api.nvim_buf_is_valid(bufnr) then
      local regions = regions_mod.parse(bufnr)
      highlights.apply(bufnr, regions, config.options)
      folding.setup_folds(bufnr, regions)
      vim.b[bufnr].region_list = regions
    end
  end))
end

--- Public setup function
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)

  local group = vim.api.nvim_create_augroup("RegionHighlight", { clear = true })

  -- Primary trigger: FileType fires after filetype is detected and file is read,
  -- guaranteeing treesitter is ready and filetype is non-empty.
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      -- Reset so auto-folds re-apply on filetype change / file reload
      vim.b[ev.buf].region_initial_fold_done = false
      process_buffer(ev.buf, true)
      if vim.b[ev.buf].region_list then
        folding.install_fold_options()
      end
    end,
  })

  -- When entering a buffer (e.g., switching tabs) - re-apply highlights and fold options
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      if not vim.b[bufnr].region_initial_fold_done then
        -- Buffer entered before FileType had a chance to process it; try now.
        -- (This also handles buffers opened in the background.)
        process_buffer(bufnr, true)
      end
      -- Re-install fold options (window-local, must be set per-window)
      if vim.b[bufnr].region_list then
        folding.install_fold_options()
        if not vim.b[bufnr].region_initial_fold_done then
          local regions = vim.b[bufnr].region_list
          folding.apply_initial_folds(bufnr, regions, config.options)
        else
          highlights.apply(bufnr, vim.b[bufnr].region_list, config.options)
        end
      end
    end,
  })

  -- BufWinEnter: install fold options and apply initial folds when buffer appears in a window
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      if vim.b[bufnr].region_list then
        folding.install_fold_options()
      end
      local regions = vim.b[bufnr].region_list
      if regions and not vim.b[bufnr].region_initial_fold_done then
        folding.apply_initial_folds(bufnr, regions, config.options)
      end
    end,
  })

  -- Release fold data when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      folding.clear_folds(ev.buf)
    end,
  })

  -- Re-apply after colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
          local regions = vim.b[bufnr].region_list
          if regions then
            highlights.apply(bufnr, regions, config.options)
          end
        end
      end
    end,
  })

  -- Debounced refresh on text change
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(ev)
      schedule_refresh(ev.buf)
    end,
  })
end

return M
