local M = {}

M.defaults = {
  fold_all = false,
  colors = nil,         -- nil = auto-tint; false = no coloring; table = user colors
  refresh_debounce = 300, -- ms to wait before re-processing after a text change
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
