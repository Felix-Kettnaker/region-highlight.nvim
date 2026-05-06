-- Minimal init for running tests with plenary
local deps_dir = vim.fn.stdpath("data") .. "/site/pack/test_deps/start"

-- Install plenary if not present
if not vim.uv.fs_stat(deps_dir .. "/plenary.nvim") then
  vim.notify("Installing plenary.nvim for tests...")
  vim.fn.mkdir(deps_dir, "p")
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/nvim-lua/plenary.nvim",
    deps_dir .. "/plenary.nvim",
  })
end

vim.opt.rtp:prepend(deps_dir .. "/plenary.nvim")
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Ensure treesitter is available
pcall(vim.cmd, "packadd nvim-treesitter")
