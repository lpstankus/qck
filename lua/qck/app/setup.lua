local terminal = require("qck.app.terminal.service")
local ui = require("qck.ui")
local tabbar = require("qck.ui.tabbar")
local storage = require("qck.tasks.storage")
local keymaps = require("qck.shared.keymaps")
local notify = require("qck.shared.notify").notify

local setup = {}

local ok, Snacks = pcall(require, "snacks")
if not ok then error("QCK: snacks.nvim is required") end
terminal.set_snacks(Snacks)
ui.setup()
ui.set_terminal_user_mappings({})
tabbar.set_user_mappings({})

---@param mappings table|nil
---@return nil
local function apply_mappings(mappings)
  mappings = keymaps.parse(mappings)
  ui.set_terminal_user_mappings(mappings)
  tabbar.set_user_mappings(mappings)
  ui.apply_terminal_user_mappings()
  tabbar.apply_user_mappings()
end

---@param mappings table|nil
---@return boolean
function setup.initialize(mappings)
  apply_mappings(mappings)

  local ok_load, load_err = storage.load()
  if not ok_load then
    notify(("failed to load workspace storage: %s; run qck.clear_storage() to reset persisted workspace data"):format(load_err or "unknown error"), vim.log.levels.WARN)
    return false
  end

  return true
end
return setup
