local M = {}

--- Get a map from 0-indexed line numbers to the comment text on that line.
--- Uses treesitter if available, falls back to treating all lines as comments.
---@param bufnr integer
---@return table<integer, string> Map of {line_0indexed -> text_of_comment_on_that_line}
local function get_comment_lines(bufnr)
  local comment_lines = {}

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    -- Fallback: treat all lines as potential comment lines
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for i, line in ipairs(lines) do
      comment_lines[i - 1] = line
    end
    return comment_lines
  end

  -- parse() populates injection trees (e.g. <script> in Vue, heredocs, etc.)
  parser:parse()

  local function walk(node)
    local ntype = node:type()
    if ntype == "comment" or ntype:find("comment", 1, true) then
      local start_row, _, end_row, _ = node:range()
      local node_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
      for i, line in ipairs(node_lines) do
        comment_lines[start_row + i - 1] = line
      end
      -- Don't recurse into comment children
      return
    elseif ntype == "region" then
      -- GDScript: (region) spans #region...#endregion as a native AST node.
      -- Collect the first line (#region) and last line (#endregion) so our
      -- text-based matching in M.parse() can handle them normally.
      local start_row, _, end_row, _ = node:range()
      local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
      if lines[1] then comment_lines[start_row] = lines[1] end
      if end_row ~= start_row and lines[#lines] then
        comment_lines[end_row] = lines[#lines]
      end
      -- Still recurse to handle nested (region) nodes
    end
    for child in node:iter_children() do
      walk(child)
    end
  end

  -- for_each_tree walks the main tree AND all injected language trees
  -- (e.g. the <script> block in a .vue file gets its own JS/TS tree)
  parser:for_each_tree(function(tree, _)
    walk(tree:root())
  end)

  return comment_lines
end

--- Parse all regions from a buffer.
--- Returns list of region objects sorted by encounter order.
---@param bufnr integer
---@return table[] List of {start_line, end_line, depth, fold_on_load, encounter_index} (0-indexed lines)
function M.parse(bufnr)
  local comment_lines = get_comment_lines(bufnr)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  local regions = {}
  local stack = {} -- stack of open region objects
  local encounter_index = 0

  for row = 0, total_lines - 1 do
    local line = comment_lines[row]
    if line then
      -- Check #endregion BEFORE #region to avoid substring match
      if line:find("#endregion", 1, true) then
        if #stack > 0 then
          local region = table.remove(stack)
          region.end_line = row
          table.insert(regions, region)
        end
        -- else: stray #endregion, ignore
      elseif line:find("#region", 1, true) then
        encounter_index = encounter_index + 1
        local fold_on_load = line:find("#region%s+fold") ~= nil
        local region = {
          start_line = row,
          end_line = nil,
          depth = #stack + 1,
          fold_on_load = fold_on_load,
          encounter_index = encounter_index,
        }
        table.insert(stack, region)
      end
    end
  end

  -- Unclosed regions: extend to end of buffer
  for _, region in ipairs(stack) do
    region.end_line = total_lines - 1
    table.insert(regions, region)
  end

  -- Sort by start_line for consistent order
  table.sort(regions, function(a, b)
    return a.start_line < b.start_line
  end)

  return regions
end

return M
