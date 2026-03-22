---@class qck
local qck = {}
require("qck.shared.types")
local state = require("qck.terminal.state")
local terminal = require("qck.terminal.service")
local tabbar = require("qck.terminal.tabbar")
local task_form = require("qck.tasks.form")
local storage = require("qck.tasks.storage")
local app_setup = require("qck.app.setup")
local targets = require("qck.app.targets")
require("qck.app.focus").setup()

local notify = require("qck.shared.notify").notify
local resolve_open_target_id = targets.resolve_open_target_id
local resolve_close_target_id = targets.resolve_close_target_id

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
    storage.workspaces = {}
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

---Create a new qck terminal with the next free numeric id and show it.
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
  terminal.create(state.next_free_id(), terminal.get_current_winid() ~= nil)
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

---Show a qck terminal by id, creating it first when needed.
---
---Parameters:
---  - `id`: Optional terminal id. When omitted, qck reuses the current terminal or picks a sensible fallback.
---
---Example:
---```lua
---require("qck").open(2)
---require("qck").open()
---```
---@param id? number Terminal id to open or create.
---@return nil
function qck.open(id)
  local target_id = resolve_open_target_id(id)
  if not target_id then
    return
  end

  terminal.open(target_id)
end

---Close an open qck terminal window and remove that terminal from qck state.
---
---Parameters:
---  - `id`: Optional terminal id to close. When omitted, qck uses the current terminal.
---
---Example:
---```lua
---require("qck").close(2)
---require("qck").close()
---```
---@param id? number Terminal id whose open window should be closed.
---@return nil
function qck.close(id)
  local target_id = resolve_close_target_id(id)
  if not target_id then
    return
  end

  terminal.close_if_open(target_id)
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
  local current_id = state.get_current_id()
  if not current_id then
    local ids = state.live_ids()
    current_id = ids[1]
    state.set_current_id(current_id)
  end

  if not current_id then
    terminal.open(state.next_free_id())
    return
  end

  terminal.toggle(current_id)
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
  local target_id = state.get_cycle_id(1)
  if not target_id then return end

  terminal.open(target_id, true)
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
  local target_id = state.get_cycle_id(-1)
  if not target_id then return end

  terminal.open(target_id, true)
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
  local tab_win = tabbar.get_winid()
  local term_win = terminal.get_current_winid()
  local current_win = vim.api.nvim_get_current_win()

  if tab_win and current_win == tab_win then
    if term_win then
      vim.api.nvim_set_current_win(term_win)
    end
    return
  end

  if term_win and current_win == term_win then
    if tab_win then
      vim.api.nvim_set_current_win(tab_win)
    end
    return
  end

  if term_win then
    vim.api.nvim_set_current_win(term_win)
    return
  end

  if tab_win then
    vim.api.nvim_set_current_win(tab_win)
  end
end

return qck
