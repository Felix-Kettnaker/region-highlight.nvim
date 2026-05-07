local config = require("region-highlight.config")
local regions_mod = require("region-highlight.regions")
local highlights = require("region-highlight.highlights")
local folding = require("region-highlight.folding")

local M = {}

-- Debounce timer per buffer
local timers = {}

--- Set up matchit % jumping between #region / #endregion
---@param bufnr integer
local function setup_matchit(bufnr)
  local pair = "#region\\>:#endregion"
  local existing = vim.b[bufnr].match_words or ""
  if not existing:find(pair, 1, true) then
    vim.b[bufnr].match_words = existing ~= "" and (existing .. "," .. pair) or pair
  end
end
M.setup_matchit = setup_matchit

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
  setup_matchit(bufnr)

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
  timer:start(config.options.refresh_debounce, 0, vim.schedule_wrap(function()
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

  -- Register the decoration provider once; it renders highlights ephemerally
  -- each frame using the row→hl map populated by highlights.apply().
  highlights.setup_provider()

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
        folding.install_fold_options(ev.buf)
      end
    end,
  })

  -- When entering a buffer (e.g., switching tabs) - re-install fold options.
  -- install_fold_options(bufnr) will NOT reset foldlevel if initial folds are done,
  -- so manually-closed folds are preserved.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      if vim.b[bufnr].region_list then
        folding.install_fold_options(bufnr)
      elseif vim.api.nvim_get_option_value("filetype", { buf = bufnr }) ~= "" then
        -- Filetype is known but not yet processed (e.g. background buffer)
        process_buffer(bufnr, true)
        if vim.b[bufnr].region_list then
          folding.install_fold_options(bufnr)
        end
      end
    end,
  })

  -- BufWinEnter: install fold options and apply initial folds when buffer appears in a window.
  -- Handles background buffers where FileType fired before the buffer had a window.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      if vim.b[bufnr].region_list then
        folding.install_fold_options(bufnr)
        if not vim.b[bufnr].region_initial_fold_done then
          local regions = vim.b[bufnr].region_list
          folding.apply_initial_folds(bufnr, regions, config.options)
        end
      end
    end,
  })

  -- Release fold data and highlight map when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      folding.clear_folds(ev.buf)
      highlights.clear(ev.buf)
    end,
  })

  -- Release window cursor cache when a window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      highlights.clear_win(tonumber(ev.match))
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
