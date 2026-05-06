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

  it("apply() respects colors=false (no highlights applied)", function()
    config.setup({ colors = false })
    local bufnr = make_buf({
      "-- #region",
      "local x = 1",
      "-- #endregion",
    })
    local rs = regions.parse(bufnr)
    highlights.apply(bufnr, rs, config.options)

    local ns = vim.api.nvim_get_namespaces()["region_highlight"]
    assert.is_not_nil(ns)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert.are.equal(0, #marks)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("apply() creates extmarks for regions with custom colors", function()
    config.setup({ colors = { "#FF0000", "#00FF00" } })
    local bufnr = make_buf({
      "-- #region",
      "local x = 1",
      "-- #endregion",
    })
    local rs = regions.parse(bufnr)
    highlights.apply(bufnr, rs, config.options)

    local ns = vim.api.nvim_get_namespaces()["region_highlight"]
    assert.is_not_nil(ns)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    -- 3 lines in the region = 3 extmarks
    assert.are.equal(3, #marks)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("clear() removes all extmarks", function()
    config.setup({ colors = { "#FF0000" } })
    local bufnr = make_buf({
      "-- #region",
      "local x = 1",
      "-- #endregion",
    })
    local rs = regions.parse(bufnr)
    highlights.apply(bufnr, rs, config.options)
    highlights.clear(bufnr)

    local ns = vim.api.nvim_get_namespaces()["region_highlight"]
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert.are.equal(0, #marks)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("cycles colors by encounter_index", function()
    config.setup({ colors = { "#FF0000", "#00FF00" } })
    local bufnr = make_buf({
      "-- #region first",
      "local x = 1",
      "-- #endregion",
      "-- #region second",
      "local y = 2",
      "-- #endregion",
      "-- #region third", -- should wrap to color[1] = #FF0000
      "local z = 3",
      "-- #endregion",
    })
    local rs = regions.parse(bufnr)
    -- Just check it doesn't error and applies marks to all lines
    assert.has_no.errors(function()
      highlights.apply(bufnr, rs, config.options)
    end)
    local ns = vim.api.nvim_get_namespaces()["region_highlight"]
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert.are.equal(9, #marks) -- 3 lines per region × 3 regions
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe("region-highlight.folding", function()
  local folding = require("region-highlight.folding")

  describe("setup_folds()", function()
    it("stores fold data in vim.b", function()
      local bufnr = make_buf({
        "-- #region",
        "local x = 1",
        "-- #endregion",
      })
      local rs = regions.parse(bufnr)
      folding.setup_folds(bufnr, rs)
      local fd = vim.b[bufnr].region_fold_data
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
      local fd = vim.b[bufnr].region_fold_data
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
      local fd = vim.b[bufnr].region_fold_data
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
      local fd = vim.b[bufnr].region_fold_data
      assert.are.equal(1, fd.levels[1])
      assert.are.equal(2, fd.levels[2])
      assert.are.equal(2, fd.levels[3])
      assert.are.equal(2, fd.levels[4])
      assert.are.equal(1, fd.levels[5])
      assert.are.equal(1, fd.starts[1])
      assert.are.equal(2, fd.starts[2])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("no fold data is set when regions list is empty", function()
      local bufnr = make_buf({ "local x = 1" })
      folding.setup_folds(bufnr, {})
      local fd = vim.b[bufnr].region_fold_data
      assert.is_not_nil(fd) -- still set, just empty starts
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
  end)

  it("merges user options over defaults", function()
    config.setup({ fold_all = true, colors = false })
    assert.are.equal(true, config.options.fold_all)
    assert.are.equal(false, config.options.colors)
  end)
end)
