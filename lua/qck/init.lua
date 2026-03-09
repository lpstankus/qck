---@class qck
local qck = {}
require("qck.shared.types")
local state = require("qck.terminal.state")
local terminal = require("qck.terminal.service")
local tabbar = require("qck.terminal.tabbar")
local task_form = require("qck.tasks.form")
local storage = require("qck.tasks.storage")
local tasks = require("qck.tasks.init")
local app_setup = require("qck.app.setup")
local targets = require("qck.app.targets")
require("qck.app.focus").setup()

local config = app_setup.config
local notify = require("qck.shared.notify").notify
local resolve_open_target_id = targets.resolve_open_target_id
local resolve_close_target_id = targets.resolve_close_target_id

---@alias qck.MappingMode "n"|"t"
---@class qck.MappingSpec
---@field rhs string|function Mapping rhs.
---@field mode? qck.MappingMode|qck.MappingMode[] Terminal modes to apply (`n`, `t`, or both). Defaults to both when omitted.
---@class qck.SetupOpts
---@field mappings? table<string, string|function|qck.MappingSpec> Buffer-local mappings for qck buffers.

---Configure qck behavior.
---Mappings defined here are active inside qck terminal and tabbar buffers.
---For terminal buffers, mappings default to both normal (`n`) and terminal (`t`) modes.
---To scope terminal mapping modes, use `{ rhs = ..., mode = "n" }`, `{ rhs = ..., mode = "t" }`, or `{ rhs = ..., mode = { "n", "t" } }`.
---Tabbar mappings are always applied in normal mode (`n`).
---Calling setup again replaces previously configured qck buffer-local mappings.
---Invalid options are ignored with error notifications.
---@param opts? qck.SetupOpts
---@return nil
function qck.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    notify("setup(opts): opts must be a table", vim.log.levels.ERROR)
    return
  end

  app_setup.initialize(opts and opts.mappings)
end

---Clear persisted qck data for the current workspace.
---This operation is explicit and user-triggered; no automatic storage reset is performed.
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

---Create a new qck terminal using the next available numeric id.
---If another qck terminal window is currently visible, that window is hidden first.
---When a qck terminal window is already open, preserves normal mode across the new terminal switch.
---When qck is closed, default terminal-mode entry behavior is preserved.
---@param _opts? table Optional compatibility parameter (currently ignored).
---@return nil
function qck.new(_opts)
  terminal.create(state.next_free_id(), {
    preserve_mode = terminal.get_current_winid() ~= nil,
  })
end

---Open a floating form to create a workspace-scoped task.
---The form captures task name + command string, supports `<Tab>`/`<S-Tab>` field cycling,
---and allows normal/insert mode switching while editing.
---Saved tasks are persisted only for the current workspace.
---@return nil
function qck.new_task()
  task_form.open()
end

---Open a terminal by id.
---If the id exists, opens the existing terminal; if it does not exist, creates and opens it.
---When omitted, opens the current terminal, otherwise the first live terminal, or creates a new one.
---When switching ids, the previously current visible terminal window is hidden.
---@param id? number Terminal id to open or create.
---@return nil
function qck.open(id)
  local target_id = resolve_open_target_id(id)
  if not target_id then
    return
  end

  terminal.open(target_id)
end

---Close a terminal window by id only if its window is currently open.
---If the id exists but the window is already closed/hidden, this is a no-op with a warning.
---If `id` is omitted, uses the current terminal id.
---Successful close removes the terminal record from qck state.
---@param id? number Terminal id whose open window should be closed.
---@return nil
function qck.close(id)
  local target_id = resolve_close_target_id(id)
  if not target_id then
    return
  end

  terminal.close_if_open(target_id)
end

---Toggle visibility of the current terminal.
---If none exists, a new terminal is created and opened.
---If no current id is set but live terminals exist, selects the first live id then toggles it.
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

---Switch to the next live terminal id (cyclic order).
---When cycling from normal mode, the destination terminal stays in normal mode.
---No-op when no live terminals exist.
---@return nil
function qck.cycle_next()
  local target_id = state.get_cycle_id(1)
  if not target_id then return end

  terminal.open(target_id, { preserve_mode = true })
end

---Switch to the previous live terminal id (cyclic order).
---When cycling from normal mode, the destination terminal stays in normal mode.
---No-op when no live terminals exist.
---@return nil
function qck.cycle_prev()
  local target_id = state.get_cycle_id(-1)
  if not target_id then return end

  terminal.open(target_id, { preserve_mode = true })
end

---Toggle focus between the current qck terminal window and the qck tab bar window.
---If only one is available, focus that one; if neither exists, this is a no-op.
---This function does not create/open windows.
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
