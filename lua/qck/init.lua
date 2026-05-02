---@class qck
local qck = {}
require("qck.shared.types")
local ui = require("qck.ui")
local task_form = require("qck.tasks.form")
local task_runner = require("qck.tasks.runner")
local storage = require("qck.tasks.storage")
local app_setup = require("qck.app.setup")
local app_terminal = require("qck.app.terminal")

local notify = require("qck.shared.notify").notify

---@alias qck.MappingMode "n"|"t"
---@class qck.MappingSpec
---@field rhs string|function Mapping rhs.
---@field mode? qck.MappingMode|qck.MappingMode[] Terminal modes to apply (`n`, `t`, or both). Defaults to both when omitted.
---@class qck.SetupOpts
---@field mappings? table<string, string|function|qck.MappingSpec> Buffer-local mappings for qck buffers.

---Configure qck's buffer-local behavior, mainly custom mappings for qck windows.
---
---Parameters:
---  - `opts`: Optional setup table.
---  - `opts.mappings`: Keymaps to apply inside qck terminal buffers and the tab bar.
---
---Example:
---```lua
---require("qck").setup({
---  mappings = {
---    ["<leader>tn"] = "<cmd>lua require('qck').cycle_next()<CR>",
---    ["<Esc>"] = { rhs = "<C-\\><C-n>", mode = "t" },
---  },
---})
---```
---@param opts? qck.SetupOpts
---@return nil
function qck.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    notify("setup(opts): opts must be a table", vim.log.levels.ERROR)
    return
  end

  app_setup.initialize(opts and opts.mappings)
end

---Delete qck's saved task data for the current working directory.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").clear_storage()
---```
---@return nil
function qck.clear_storage()
  local ok_load, load_err = storage.load()
  if not ok_load then
    notify(
      ("storage is invalid/unavailable (%s); rewriting storage with empty state"):format(
        load_err or "unknown error"
      ),
      vim.log.levels.WARN
    )
    storage.ok = true
    storage.workspaces = vim.empty_dict()
    storage.last_error = nil
  end

  local workspace = vim.fn.getcwd()
  storage.clear_workspace(workspace)

  local ok_save, save_err = storage.save()
  if not ok_save then
    notify(
      ("failed to clear storage for `%s`: %s"):format(workspace, save_err or "unknown error"),
      vim.log.levels.ERROR
    )
    return
  end

  notify(("cleared storage for `%s`"):format(workspace), vim.log.levels.INFO)
end

---Create a new qck terminal tab and show it.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").new()
---```
---@return nil
function qck.new()
  app_terminal.create_and_attach(ui.is_visible())
end

---Open the task-creation form for adding a saved task in this workspace.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").new_task()
---```
---@return nil
function qck.new_task()
  task_form.open()
end

---Open the task runner selector for saved tasks in this workspace.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").run_task()
---```
---@return nil
function qck.run_task()
  task_runner.open()
end

---Show the active qck terminal, creating a new one when none exist.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").open()
---```
---@return nil
function qck.open()
  app_terminal.open_active_or_create()
end

---Close the active qck terminal tab and remove it from qck state.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").close()
---```
---@return nil
function qck.close()
  local ok, err = ui.close_active()
  if ok then
    return
  end

  if err == "no active tab" then
    notify("no current terminal selected (no-op)", vim.log.levels.WARN)
    return
  end

  notify(("failed to close current terminal: %s"):format(tostring(err)), vim.log.levels.ERROR)
end

---Hide the current qck terminal if it is visible, or show it if it is hidden.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").toggle()
---```
---@return nil
function qck.toggle()
  app_terminal.toggle_active_or_create()
end

---Move to the next live qck terminal, wrapping around at the end.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").cycle_next()
---```
---@return nil
function qck.cycle_next()
  ui.cycle(1)
end

---Move to the previous live qck terminal, wrapping around at the beginning.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").cycle_prev()
---```
---@return nil
function qck.cycle_prev()
  ui.cycle(-1)
end

---Switch cursor focus between the current qck terminal and its tab bar.
---
---Parameters:
---  - None.
---
---Example:
---```lua
---require("qck").switch_focus()
---```
---@return nil
function qck.switch_focus()
  ui.toggle_tabbar_focus()
end

return qck
