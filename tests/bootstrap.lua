local M = {}

local root = vim.fn.getcwd()

function M.setup_xdg(name)
  local base = root .. "/tests/.tmp/" .. name
  vim.env.XDG_CONFIG_HOME = base .. "/config"
  vim.env.XDG_DATA_HOME = base .. "/data"
  vim.env.XDG_STATE_HOME = base .. "/state"
  vim.env.XDG_CACHE_HOME = base .. "/cache"

  vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, "p")
  vim.fn.mkdir(vim.env.XDG_DATA_HOME, "p")
  vim.fn.mkdir(vim.env.XDG_STATE_HOME, "p")
  vim.fn.mkdir(vim.env.XDG_CACHE_HOME, "p")

  local state_root = vim.env.XDG_STATE_HOME .. "/nvim"
  local swap_dir = state_root .. "/swap"
  local backup_dir = state_root .. "/backup"
  local undo_dir = state_root .. "/undo"
  local view_dir = state_root .. "/view"

  vim.fn.mkdir(swap_dir, "p")
  vim.fn.mkdir(backup_dir, "p")
  vim.fn.mkdir(undo_dir, "p")
  vim.fn.mkdir(view_dir, "p")

  vim.o.backupdir = backup_dir .. "//"
  vim.o.directory = swap_dir .. "//"
  vim.o.undodir = undo_dir .. "//"
  vim.o.viewdir = view_dir .. "//"
  vim.o.shadafile = "NONE"
end

return M
