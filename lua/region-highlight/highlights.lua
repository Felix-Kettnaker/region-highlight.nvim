local M = {}

local NS = vim.api.nvim_create_namespace("region_highlight")

--- Parse a 24-bit integer color into R, G, B components
---@param color integer
---@return integer, integer, integer
local function int_to_rgb(color)
  local r = math.floor(color / 65536) % 256
  local g = math.floor(color / 256) % 256
  local b = color % 256
  return r, g, b
end

--- Blend two hex colors with a given alpha (0=c1, 1=c2)
---@param r1 integer
---@param g1 integer
---@param b1 integer
---@param r2 integer
---@param g2 integer
---@param b2 integer
---@param alpha number 0..1
---@return string hex color
local function blend(r1, g1, b1, r2, g2, b2, alpha)
  local r = math.min(255, math.max(0, math.floor(r1 + (r2 - r1) * alpha)))
  local g = math.min(255, math.max(0, math.floor(g1 + (g2 - g1) * alpha)))
  local b = math.min(255, math.max(0, math.floor(b1 + (b2 - b1) * alpha)))
  return string.format("#%02X%02X%02X", r, g, b)
end

--- Generate automatic tint colors for up to `max_depth` levels
---@param max_depth integer
---@return table<integer, string>|nil Map of depth -> hex color, or nil if no bg
local function auto_tint_colors(max_depth)
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal_hl.bg
  if not bg or bg == -1 then
    return nil
  end

  local r, g, b = int_to_rgb(bg)
  local luminance = 0.299 * r + 0.587 * g + 0.114 * b
  local is_dark = luminance < 128

  local colors = {}
  for depth = 1, max_depth do
    local alpha = 0.05 * depth
    if is_dark then
      colors[depth] = blend(r, g, b, 255, 255, 255, alpha)
    else
      colors[depth] = blend(r, g, b, 0, 0, 0, alpha)
    end
  end
  return colors
end

--- Ensure a highlight group exists with the given background color
---@param name string
---@param bg_hex string
local function ensure_hl_group(name, bg_hex)
  vim.api.nvim_set_hl(0, name, { bg = bg_hex })
end

--- Clear all region highlights from a buffer
---@param bufnr integer
function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
end

--- Apply region highlights to a buffer
---@param bufnr integer
---@param regions table[] from regions.parse()
---@param opts table config options
function M.apply(bufnr, regions, opts)
  M.clear(bufnr)

  if not regions or #regions == 0 then
    return
  end

  if opts.colors == false then
    return
  end

  -- Build color map for all regions upfront
  local region_colors = {}

  if type(opts.colors) == "table" and #opts.colors > 0 then
    for _, region in ipairs(regions) do
      local idx = ((region.encounter_index - 1) % #opts.colors) + 1
      region_colors[region.encounter_index] = {
        color = opts.colors[idx],
        hl_name = "RegionHighlight_custom_" .. idx,
      }
    end
  else
    -- Auto-tint: compute per depth
    local max_depth = 0
    for _, region in ipairs(regions) do
      if region.depth > max_depth then max_depth = region.depth end
    end
    local tints = auto_tint_colors(max_depth)
    if not tints then return end

    for _, region in ipairs(regions) do
      region_colors[region.encounter_index] = {
        color = tints[region.depth],
        hl_name = "RegionHighlight_depth_" .. region.depth,
      }
    end
  end

  -- Ensure all hl groups exist
  local created_groups = {}
  for _, info in pairs(region_colors) do
    if not created_groups[info.hl_name] then
      ensure_hl_group(info.hl_name, info.color)
      created_groups[info.hl_name] = true
    end
  end

  -- Apply extmarks
  for _, region in ipairs(regions) do
    local info = region_colors[region.encounter_index]
    if info then
      for row = region.start_line, region.end_line do
        vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
          end_row = row,
          line_hl_group = info.hl_name,
          priority = 10 + region.depth,
        })
      end
    end
  end
end

return M
