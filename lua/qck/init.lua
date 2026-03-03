---@class qck
local qck = {}
require("qck.types")
local state = require("qck.state")
local terminal = require("qck.terminal")
local tabbar = require("qck.tabbar")
local task_form = require("qck.task_form")
local autocmd = require("qck.autocmd")
local storage = require("qck.storage")
local tasks = require("qck.tasks")

local ok, Snacks = pcall(require, "snacks")
if not ok then error("QCK: snacks.nvim is required") end
terminal.set_snacks(Snacks)
terminal.set_user_mappings({})
tabbar.set_user_mappings({})

local config = {
  mappings = {},
}

---@param msg string
---@param level integer|nil
---@return nil
local function notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

local focus_cleanup_in_progress = false

---@param id number
---@return boolean
local function is_valid_id(id)
  return type(id) == "number" and id > 0 and id % 1 == 0
end

---@param id number|nil
---@return integer|nil, boolean
local function parse_id_arg(id)
  if id == nil then
    return nil, true
  end

  if not is_valid_id(id) then
    notify("id must be a positive integer", vim.log.levels.ERROR)
    return nil, false
  end

  return id, true
end

---@param id number|nil
---@return integer|nil
local function resolve_open_target_id(id)
  local target_id, parsed = parse_id_arg(id)
  if not parsed then
    return nil
  end
  if target_id then
    return target_id
  end

  target_id = state.get_current_id()
  if target_id then
    return target_id
  end

  local ids = state.live_ids()
  return ids[1] or state.next_free_id()
end

---@param id number|nil
---@return integer|nil
local function resolve_close_target_id(id)
  local target_id, parsed = parse_id_arg(id)
  if not parsed then
    return nil
  end
  if target_id then
    return target_id
  end

  target_id = state.get_current_id()
  if target_id then
    return target_id
  end

  notify("no current terminal selected (no-op)", vim.log.levels.WARN)
  return nil
end

local DEFAULT_MAPPING_MODES = { "n", "t" }
local VALID_MAPPING_MODES = {
  n = true,
  t = true,
}

---@param mode any
---@param lhs string
---@return string[]|nil
local function parse_mapping_modes(mode, lhs)
  if mode == nil then
    local default_modes = {}
    for _, value in ipairs(DEFAULT_MAPPING_MODES) do
      default_modes[#default_modes + 1] = value
    end
    return default_modes
  end

  local requested_modes = {}
  if type(mode) == "string" then
    requested_modes[1] = mode
  elseif type(mode) == "table" then
    for _, value in ipairs(mode) do
      requested_modes[#requested_modes + 1] = value
    end
  else
    notify(
      ("setup(opts): map `%s`.mode must be `n`, `t`, or a list of them"):format(lhs),
      vim.log.levels.ERROR
    )
    return nil
  end

  if #requested_modes == 0 then
    notify(
      ("setup(opts): map `%s`.mode list must not be empty"):format(lhs),
      vim.log.levels.ERROR
    )
    return nil
  end

  local seen_modes = {}
  for _, value in ipairs(requested_modes) do
    if type(value) ~= "string" or not VALID_MAPPING_MODES[value] then
      notify(
        ("setup(opts): map `%s`.mode supports only `n` and `t`"):format(lhs),
        vim.log.levels.ERROR
      )
      return nil
    end
    seen_modes[value] = true
  end

  local parsed_modes = {}
  for _, value in ipairs(DEFAULT_MAPPING_MODES) do
    if seen_modes[value] then
      parsed_modes[#parsed_modes + 1] = value
    end
  end

  return parsed_modes
end

local function parse_mappings(mappings)
  if mappings == nil then
    return {}
  end

  if type(mappings) ~= "table" then
    notify("setup(opts): opts.mappings must be a table", vim.log.levels.ERROR)
    return {}
  end

  local parsed = {}
  for lhs, mapping in pairs(mappings) do
    if type(lhs) ~= "string" then
      notify("setup(opts): mapping lhs must be a string", vim.log.levels.ERROR)
    else
      local rhs = mapping
      local mode = nil
      if type(mapping) == "table" then
        rhs = mapping.rhs
        mode = mapping.mode
      end

      if type(rhs) ~= "function" and type(rhs) ~= "string" then
        notify(
          ("setup(opts): map `%s`.rhs must be a function or string"):format(lhs),
          vim.log.levels.ERROR
        )
      else
        local terminal_modes = parse_mapping_modes(mode, lhs)
        if terminal_modes then
          parsed[lhs] = {
            rhs = rhs,
            terminal_modes = terminal_modes,
          }
        end
      end
    end
  end

  return parsed
end

local function focus_current_terminal()
  local term_win = terminal.get_current_winid()
  if not term_win then
    return
  end
  vim.api.nvim_set_current_win(term_win)
end

tabbar.set_actions({
  open = function(id) terminal.open(id) end,
  delete = function(id) terminal.delete(id) end,
  move_up = function(id) terminal.move_up(id) end,
  move_down = function(id) terminal.move_down(id) end,
  close_current = function() terminal.hide_current_if_open() end,
  focus_current = focus_current_terminal,
})

local function hide_if_focus_left_qck_windows()
  if focus_cleanup_in_progress then
    return
  end

  local term_win = terminal.get_current_winid()
  local tab_win = tabbar.get_winid()
  if not term_win and not tab_win then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  if (term_win and current_win == term_win) or (tab_win and current_win == tab_win) then
    return
  end

  focus_cleanup_in_progress = true

  local ok_term, term_err = pcall(function() terminal.hide_current_if_open() end)
  local ok_tabbar, tabbar_err = pcall(function() tabbar.hide() end)

  vim.schedule(function()
    focus_cleanup_in_progress = false
  end)

  if not ok_term then
    notify(
      ("failed to hide qck terminal after focus left qck windows: %s"):format(tostring(term_err)),
      vim.log.levels.ERROR
    )
  end

  if not ok_tabbar then
    notify(
      ("failed to hide qck tabbar after focus left qck windows: %s"):format(tostring(tabbar_err)),
      vim.log.levels.ERROR
    )
  end
end

autocmd.create({ "WinEnter", "BufEnter", "TabEnter" }, {
  callback = hide_if_focus_left_qck_windows,
})

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

  config.mappings = parse_mappings(opts and opts.mappings)

  tasks.set_storage(storage)
  tasks.set_definitions({})
  terminal.set_user_mappings(config.mappings)
  tabbar.set_user_mappings(config.mappings)
  terminal.apply_user_mappings()
  tabbar.apply_user_mappings()

  local ok_load, load_err = storage.load()
  if not ok_load then
    notify(
      (
        "failed to load workspace storage: %s; run qck.clear_storage() to reset persisted workspace data"
      ):format(load_err or "unknown error"),
      vim.log.levels.WARN
    )
  else
    tasks.hydrate_workspace_tasks(vim.fn.getcwd())
  end
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
