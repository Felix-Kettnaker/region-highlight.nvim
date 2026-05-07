local regions = require("region-highlight.regions")
local highlights = require("region-highlight.highlights")
local config = require("region-highlight.config")

-- Helper: create a scratch buffer with given lines
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  -- Set filetype so treesitter might work, but tests don't depend on it
  vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr })
  return bufnr
end

describe("region-highlight.regions", function()
  describe("parse()", function()
    it("detects a simple region", function()
      local bufnr = make_buf({
        "-- #region",
        "local x = 1",
        "-- #endregion",
      })
      local result = regions.parse(bufnr)
      assert.are.equal(1, #result)
      assert.are.equal(0, result[1].start_line)
      assert.are.equal(2, result[1].end_line)
      assert.are.equal(1, result[1].depth)
      assert.are.equal(false, result[1].fold_on_load)
      assert.are.equal(1, result[1].encounter_index)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("detects fold_on_load from '#region fold'", function()
      local bufnr = make_buf({
        "-- #region fold",
        "local x = 1",
        "-- #endregion",
      })
      local result = regions.parse(bufnr)
      assert.are.equal(1, #result)
      assert.are.equal(true, result[1].fold_on_load)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("handles nested regions", function()
      local bufnr = make_buf({
        "-- #region outer",  -- line 0
        "local a = 1",       -- line 1
        "-- #region inner",  -- line 2
        "local b = 2",       -- line 3
        "-- #endregion",     -- line 4 (closes inner)
        "local c = 3",       -- line 5
        "-- #endregion",     -- line 6 (closes outer)
      })
      local result = regions.parse(bufnr)
      assert.are.equal(2, #result)

      -- Find inner and outer
      local outer, inner
      for _, r in ipairs(result) do
        if r.depth == 1 then outer = r end
        if r.depth == 2 then inner = r end
      end

      assert.is_not_nil(outer)
      assert.is_not_nil(inner)
      assert.are.equal(0, outer.start_line)
      assert.are.equal(6, outer.end_line)
      assert.are.equal(2, inner.start_line)
      assert.are.equal(4, inner.end_line)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("handles stray #endregion gracefully", function()
      local bufnr = make_buf({
        "-- #endregion", -- stray, no matching open
        "local x = 1",
      })
      local result = regions.parse(bufnr)
      assert.are.equal(0, #result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("handles unclosed region by extending to end of buffer", function()
      local bufnr = make_buf({
        "-- #region",
        "local x = 1",
        "local y = 2",
      })
      local result = regions.parse(bufnr)
      assert.are.equal(1, #result)
      assert.are.equal(0, result[1].start_line)
      assert.are.equal(2, result[1].end_line) -- last line
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns empty table for buffer with no regions", function()
      local bufnr = make_buf({
        "local x = 1",
        "local y = 2",
      })
      local result = regions.parse(bufnr)
      assert.are.equal(0, #result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not confuse #endregion as #region start", function()
      local bufnr = make_buf({
        "-- #endregion",
        "-- #region",
        "local x = 1",
        "-- #endregion",
      })
      local result = regions.parse(bufnr)
      -- First endregion is stray (ignored), then we get one region
      assert.are.equal(1, #result)
      assert.are.equal(1, result[1].start_line)
      assert.are.equal(3, result[1].end_line)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("assigns correct encounter_index to multiple regions", function()
      local bufnr = make_buf({
        "-- #region first",
        "-- #endregion",
        "-- #region second",
        "-- #endregion",
        "-- #region third",
        "-- #endregion",
      })
      local result = regions.parse(bufnr)
      assert.are.equal(3, #result)
      -- Sort by start_line
      table.sort(result, function(a, b) return a.start_line < b.start_line end)
      assert.are.equal(1, result[1].encounter_index)
      assert.are.equal(2, result[2].encounter_index)
      assert.are.equal(3, result[3].encounter_index)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)

describe("region-highlight.highlights", function()
  before_each(function()
    config.setup({})
  end)

  it("apply() does not error on empty regions", function()
    local bufnr = make_buf({ "local x = 1" })
    assert.has_no.errors(function()
      highlights.apply(bufnr, {}, config.options)
    end)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("apply() respects colors=false (no row map built)", function()
    config.setup({ colors = false })
    local bufnr = make_buf({
      "-- #region",
      "local x = 1",
      "-- #endregion",
    })
    local rs = regions.parse(bufnr)
    highlights.apply(bufnr, rs, config.options)

    assert.is_nil(highlights.get_row_map(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("apply() builds row map covering all region lines with custom colors", function()
    config.setup({ colors = { "#FF0000", "#00FF00" } })
    local bufnr = make_buf({
      "-- #region",
      "local x = 1",
      "-- #endregion",
    })
    local rs = regions.parse(bufnr)
    highlights.apply(bufnr, rs, config.options)

    local row_map = highlights.get_row_map(bufnr)
    assert.is_not_nil(row_map)
    -- 3 lines in the region (rows 0, 1, 2) all mapped
    assert.is_not_nil(row_map[0])
    assert.is_not_nil(row_map[1])
    assert.is_not_nil(row_map[2])
    -- row 3 is outside → no entry
    assert.is_nil(row_map[3])
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("clear() removes the row map", function()
    config.setup({ colors = { "#FF0000" } })
    local bufnr = make_buf({
      "-- #region",
      "local x = 1",
      "-- #endregion",
    })
    local rs = regions.parse(bufnr)
    highlights.apply(bufnr, rs, config.options)
    assert.is_not_nil(highlights.get_row_map(bufnr))
    highlights.clear(bufnr)
    assert.is_nil(highlights.get_row_map(bufnr))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("cycles colors by encounter_index and maps all lines", function()
    config.setup({ colors = { "#FF0000", "#00FF00" } })
    local bufnr = make_buf({
      "-- #region first",  -- row 0
      "local x = 1",       -- row 1
      "-- #endregion",     -- row 2
      "-- #region second", -- row 3
      "local y = 2",       -- row 4
      "-- #endregion",     -- row 5
      "-- #region third",  -- row 6, wraps to color[1]
      "local z = 3",       -- row 7
      "-- #endregion",     -- row 8
    })
    local rs = regions.parse(bufnr)
    assert.has_no.errors(function()
      highlights.apply(bufnr, rs, config.options)
    end)
    local row_map = highlights.get_row_map(bufnr)
    assert.is_not_nil(row_map)
    -- All 9 lines should be mapped
    for row = 0, 8 do
      assert.is_not_nil(row_map[row], "expected row " .. row .. " to be in row_map")
    end
    -- region 1 and 3 share color[1] (encounter_index 1 and 3 → both map to idx 1)
    assert.are.equal(row_map[0], row_map[6])
    -- region 2 uses color[2]
    assert.are_not.equal(row_map[3], row_map[0])
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("region-highlight.folding", function()
  local folding = require("region-highlight.folding")

  describe("setup_folds()", function()
    it("stores fold data accessible via get_fold_data()", function()
      local bufnr = make_buf({
        "-- #region",
        "local x = 1",
        "-- #endregion",
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local fd = folding.get_fold_data(bufnr)
      assert.is_not_nil(fd)
      assert.is_not_nil(fd.starts)
      assert.is_not_nil(fd.levels)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("marks region start line as fold opener", function()
      local bufnr = make_buf({
        "-- #region",    -- row 0, lnum 1
        "local x = 1",
        "-- #endregion",
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local fd = folding.get_fold_data(bufnr)
      assert.are.equal(1, fd.starts[1]) -- lnum 1 starts fold of depth 1
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("sets fold levels for all lines inside a region", function()
      local bufnr = make_buf({
        "-- #region",    -- lnum 1: depth 1
        "local x = 1",   -- lnum 2: depth 1
        "-- #endregion", -- lnum 3: depth 1
        "local y = 2",   -- lnum 4: depth 0 (outside)
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local fd = folding.get_fold_data(bufnr)
      assert.are.equal(1, fd.levels[1])
      assert.are.equal(1, fd.levels[2])
      assert.are.equal(1, fd.levels[3])
      assert.are.equal(0, fd.levels[4])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("sets deeper levels for nested regions", function()
      local bufnr = make_buf({
        "-- #region outer", -- lnum 1: depth 1
        "-- #region inner", -- lnum 2: depth 2
        "local x = 1",      -- lnum 3: depth 2
        "-- #endregion",    -- lnum 4: depth 2 (inner end)
        "-- #endregion",    -- lnum 5: depth 1 (outer end)
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local fd = folding.get_fold_data(bufnr)
      assert.are.equal(1, fd.levels[1])
      assert.are.equal(2, fd.levels[2])
      assert.are.equal(2, fd.levels[3])
      assert.are.equal(2, fd.levels[4])
      assert.are.equal(1, fd.levels[5])
      assert.are.equal(1, fd.starts[1])
      assert.are.equal(2, fd.starts[2])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("no fold data starts are empty when regions list is empty", function()
      local bufnr = make_buf({ "local x = 1" })
      folding.setup_folds(bufnr, {})
      local fd = folding.get_fold_data(bufnr)
      assert.is_not_nil(fd)
      assert.are.equal(0, vim.tbl_count(fd.starts))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("foldexpr()", function()
    it("returns '>depth' for region start lines", function()
      local bufnr = make_buf({
        "-- #region",
        "local x = 1",
        "-- #endregion",
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local result = vim.api.nvim_buf_call(bufnr, function()
        return folding.foldexpr(1)
      end)
      assert.are.equal(">1", result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns level string for lines inside a region", function()
      local bufnr = make_buf({
        "-- #region",
        "local x = 1",
        "-- #endregion",
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local result = vim.api.nvim_buf_call(bufnr, function()
        return folding.foldexpr(2)
      end)
      assert.are.equal("1", result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns '0' for lines outside all regions", function()
      local bufnr = make_buf({
        "-- #region",
        "local x = 1",
        "-- #endregion",
        "local y = 2", -- lnum 4, outside
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local result = vim.api.nvim_buf_call(bufnr, function()
        return folding.foldexpr(4)
      end)
      assert.are.equal("0", result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns '0' when no fold data exists", function()
      local bufnr = make_buf({ "local x = 1" })
      local result = vim.api.nvim_buf_call(bufnr, function()
        return folding.foldexpr(1)
      end)
      assert.are.equal("0", result)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)

describe("region-highlight.config", function()
  it("has correct defaults", function()
    config.setup({})
    assert.are.equal(false, config.options.fold_all)
    assert.is_nil(config.options.colors)
    assert.are.equal(300, config.options.refresh_debounce)
  end)

  it("merges user options over defaults", function()
    config.setup({ fold_all = true, colors = false })
    assert.are.equal(true, config.options.fold_all)
    assert.are.equal(false, config.options.colors)
  end)

  it("accepts custom refresh_debounce", function()
    config.setup({ refresh_debounce = 500 })
    assert.are.equal(500, config.options.refresh_debounce)
  end)
end)

describe("region-highlight.matchit", function()
  local rh = require("region-highlight")

  it("sets b:match_words with region pair on a fresh buffer", function()
    local bufnr = make_buf({ "-- #region", "local x = 1", "-- #endregion" })
    vim.b[bufnr].match_words = nil
    rh.setup_matchit(bufnr)
    local mw = vim.b[bufnr].match_words or ""
    assert.truthy(mw:find("#region\\>:#endregion", 1, true))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("appends to existing b:match_words without overwriting", function()
    local bufnr = make_buf({ "-- #region", "local x = 1", "-- #endregion" })
    vim.b[bufnr].match_words = "if:endif,for:endfor"
    rh.setup_matchit(bufnr)
    local mw = vim.b[bufnr].match_words or ""
    assert.truthy(mw:find("if:endif,for:endfor", 1, true))
    assert.truthy(mw:find("#region\\>:#endregion", 1, true))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("does not add duplicate pair when called twice", function()
    local bufnr = make_buf({ "-- #region", "local x = 1", "-- #endregion" })
    vim.b[bufnr].match_words = nil
    rh.setup_matchit(bufnr)
    rh.setup_matchit(bufnr)
    local mw = vim.b[bufnr].match_words or ""
    -- Count occurrences: should be exactly 1
    local count = 0
    local pos = 1
    while true do
      local s = mw:find("#region", pos, true)
      if not s then break end
      count = count + 1
      pos = s + 1
    end
    assert.are.equal(1, count)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

-- Regression tests for fold initialization bugs
describe("region-highlight.folding (regression)", function()
  local folding = require("region-highlight.folding")

  -- Helper: load a buffer in the current window, returning the previous buffer
  local function load_in_window(bufnr)
    local prev = vim.api.nvim_win_get_buf(0)
    vim.api.nvim_win_set_buf(0, bufnr)
    return prev
  end

  describe("install_fold_options()", function()
    it("sets foldlevel=99 when initial folds not yet applied", function()
      local bufnr = make_buf({ "-- #region", "local x", "-- #endregion" })
      vim.wo.foldlevel = 5
      folding.install_fold_options(bufnr)
      assert.are.equal("expr", vim.wo.foldmethod)
      assert.are.equal(99, vim.wo.foldlevel)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does NOT reset foldlevel when initial folds already applied", function()
      local bufnr = make_buf({ "-- #region", "local x", "-- #endregion" })
      vim.b[bufnr].region_initial_fold_done = true
      vim.wo.foldlevel = 42
      folding.install_fold_options(bufnr)
      assert.are.equal("expr", vim.wo.foldmethod)
      assert.are.equal(42, vim.wo.foldlevel) -- preserved, not reset to 99
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("apply_initial_folds()", function()
    it("closes fold for region with fold_on_load=true", function()
      local bufnr = make_buf({ "-- #region fold", "local x = 1", "-- #endregion" })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local prev = load_in_window(bufnr)
      folding.install_fold_options(bufnr)
      folding.apply_initial_folds(bufnr, rs, { fold_all = false })
      assert.are.equal(1, vim.fn.foldclosed(1)) -- lnum 1 should be closed
      vim.api.nvim_win_set_buf(0, prev)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not close plain #region when fold_all=false", function()
      local bufnr = make_buf({ "-- #region", "local x = 1", "-- #endregion" })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local prev = load_in_window(bufnr)
      folding.install_fold_options(bufnr)
      folding.apply_initial_folds(bufnr, rs, { fold_all = false })
      assert.are.equal(-1, vim.fn.foldclosed(1)) -- should remain open
      vim.api.nvim_win_set_buf(0, prev)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("closes all folds when fold_all=true", function()
      local bufnr = make_buf({
        "-- #region",       -- lnum 1
        "local x = 1",
        "-- #endregion",
        "-- #region",       -- lnum 4
        "local y = 2",
        "-- #endregion",
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local prev = load_in_window(bufnr)
      folding.install_fold_options(bufnr)
      folding.apply_initial_folds(bufnr, rs, { fold_all = true })
      assert.are.equal(1, vim.fn.foldclosed(1))
      assert.are.equal(4, vim.fn.foldclosed(4))
      vim.api.nvim_win_set_buf(0, prev)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("runs only once per buffer (idempotent guard)", function()
      local bufnr = make_buf({ "-- #region fold", "local x = 1", "-- #endregion" })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local prev = load_in_window(bufnr)
      folding.install_fold_options(bufnr)
      folding.apply_initial_folds(bufnr, rs, { fold_all = false })
      assert.are.equal(1, vim.fn.foldclosed(1)) -- closed
      vim.cmd("normal! zo")                       -- manually reopen
      assert.are.equal(-1, vim.fn.foldclosed(1))  -- now open
      -- second call should be a no-op (done flag set)
      folding.apply_initial_folds(bufnr, rs, { fold_all = false })
      assert.are.equal(-1, vim.fn.foldclosed(1))  -- still open
      vim.api.nvim_win_set_buf(0, prev)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not reopen closed folds when install_fold_options is called again after done", function()
      local bufnr = make_buf({ "-- #region fold", "local x = 1", "-- #endregion" })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local prev = load_in_window(bufnr)
      folding.install_fold_options(bufnr)
      folding.apply_initial_folds(bufnr, rs, { fold_all = false })
      assert.are.equal(1, vim.fn.foldclosed(1)) -- closed
      -- Simulate re-entering buffer (BufEnter) calling install_fold_options again
      folding.install_fold_options(bufnr)
      assert.are.equal(1, vim.fn.foldclosed(1)) -- still closed (foldlevel not reset)
      vim.api.nvim_win_set_buf(0, prev)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)

