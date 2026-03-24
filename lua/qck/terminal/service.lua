-- Terminal-backed client primitives for the UI-owned runtime.
--
-- UI now owns registered terminal-tab runtime behavior after a successful
-- `attach_and_show(...)` handoff. This module is limited to Snacks terminal
-- creation/reopen/delete helpers, preserved-mode handling, and terminal record
-- bookkeeping that still backs the public surface.
local state = require("qck.terminal.state")
local layout = require("qck.ui.layout")
local ui_state = require("qck.ui.state")
local notify = require("qck.shared.notify").notify

local terminal = {}

local snacks = nil

---@return qck.ui|nil
local function get_ui()
  local ok, ui = pcall(require, "qck.ui")
  if ok then
    return ui
  end

  return nil
end

---@param callback fun(): any
---@return any
local function with_ui_focus_leave_suppressed(callback)
  local ui = get_ui()
  if ui and type(ui.with_suppressed_focus_leave) == "function" then
    return ui.with_suppressed_focus_leave(callback)
  end

  return callback()
end

---@param rec qck.TerminalRecord|nil
---@return qck.TerminalHandle|nil
local function get_terminal_handle(rec)
  if not rec or type(rec) ~= "table" then
    return nil
  end
  if not rec.win then
    return nil
  end
  return rec.win
end

---@param handle qck.TerminalHandle|table|nil
---@return nil
local function safe_close_handle(handle)
  if type(handle) ~= "table" then
    return
  end

  if type(handle.close) == "function" then
    pcall(function() handle:close() end)
    return
  end

  if type(handle.win) == "number" and vim.api.nvim_win_is_valid(handle.win) then
    pcall(vim.api.nvim_win_close, handle.win, true)
  end

  if type(handle.buf) == "number" and vim.api.nvim_buf_is_valid(handle.buf) then
    pcall(vim.api.nvim_buf_delete, handle.buf, { force = true })
  end
end

---@param snacks_impl { terminal?: { open?: fun(cmd: qck.Command|nil, opts: table|nil): qck.TerminalHandle|nil } }|nil
---@return nil
function terminal.set_snacks(snacks_impl)
  if snacks_impl ~= nil and type(snacks_impl) ~= "table" then
    snacks = nil
    return
  end
  snacks = snacks_impl
end

local function terminal_winid(rec)
  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    return nil
  end

  if type(rec_win.win) == "number" and vim.api.nvim_win_is_valid(rec_win.win) then
    return rec_win.win
  end

  if type(rec_win.win) == "function" then
    local ok, win = pcall(function() return rec_win:win() end)
    if ok and type(win) == "number" and vim.api.nvim_win_is_valid(win) then
      return win
    end
  end

  return nil
end

---@param mode string|nil
---@return boolean
local function is_normal_mode(mode)
  return type(mode) == "string" and mode:sub(1, 1) == "n"
end

---@return "normal"|nil
local function capture_mode_intent()
  local ok, mode_info = pcall(vim.api.nvim_get_mode)
  if not ok or type(mode_info) ~= "table" then
    return nil
  end

  if is_normal_mode(mode_info.mode) then
    return "normal"
  end

  return nil
end

---@param rec qck.TerminalRecord|nil
---@param mode_intent "normal"|nil
---@return nil
local function restore_mode_intent(rec, mode_intent)
  if mode_intent ~= "normal" then
    return
  end

  local winid = terminal_winid(rec)
  if not winid then
    return
  end

  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.cmd, "stopinsert")
end

local function remove_terminal_record(id)
  state.remove_terminal(id)
  state.update_current_after_removal(id)
end

---@return boolean
local function ensure_snacks()
  if type(snacks) ~= "table" then
    notify("snacks.nvim is required", vim.log.levels.ERROR)
    return false
  end

  if type(snacks.terminal) ~= "table" then
    notify("snacks.nvim terminal API is unavailable", vim.log.levels.ERROR)
    return false
  end

  if type(snacks.terminal.open) ~= "function" then
    notify("snacks.nvim terminal.open is unavailable", vim.log.levels.ERROR)
    return false
  end

  return true
end

---@param id integer
---@param preserve_mode boolean|nil
---@return qck.TerminalRecord|nil
function terminal.create(id, preserve_mode)
  return with_ui_focus_leave_suppressed(function()
    preserve_mode = preserve_mode == true
    local mode_intent = preserve_mode and capture_mode_intent() or nil
    local ui = get_ui()

    if not snacks or not ensure_snacks() then return nil end
    if not ui or type(ui.attach_and_show) ~= "function" then
      notify("qck ui is unavailable", vim.log.levels.ERROR)
      return nil
    end
    if type(ui.setup) == "function" then
      ui.setup()
    end

    local rec = {
      win = nil,
      meta = {},
    }

    local term_opts = {
      interactive = true,
      auto_close = true,
      count = id,
      win = vim.tbl_extend("force", layout.build_initial_terminal_config(), {
        position = "float",
      }),
    }

    local ok_open, term_or_err = pcall(snacks.terminal.open, nil, term_opts)
    if not ok_open or not term_or_err then
      local msg = ok_open and "failed to open terminal"
        or ("failed to open terminal: " .. tostring(term_or_err))
      notify(msg, vim.log.levels.ERROR)
      return nil
    end

    rec.win = term_or_err
    state.set_terminal(id, rec)

    local rec_win = get_terminal_handle(rec)
    if not rec_win then
      state.remove_terminal(id)
      safe_close_handle(term_or_err)
      notify(("failed to initialize terminal %d handle"):format(id), vim.log.levels.ERROR)
      return nil
    end

    local tab_id, attach_err = ui.attach_and_show("terminal", rec_win)
    if not tab_id then
      state.remove_terminal(id)
      safe_close_handle(rec_win)
      notify(attach_err or ("failed to attach terminal %d to ui"):format(id), vim.log.levels.ERROR)
      return nil
    end

    state.set_tab_id(id, tab_id)
    state.sync_current_from_ui()
    restore_mode_intent(rec, mode_intent)

    return rec
  end)
end

---@param id integer
---@return qck.TerminalRecord|nil
function terminal.ensure(id)
  local rec = state.get_terminal(id)
  if state.is_valid_record(rec) then
    return rec
  end

  remove_terminal_record(id)
  return terminal.create(id)
end

---@param id integer
---@param preserve_mode boolean|nil
---@return qck.TerminalRecord|nil
function terminal.open(id, preserve_mode)
  return with_ui_focus_leave_suppressed(function()
    preserve_mode = preserve_mode == true
    local mode_intent = preserve_mode and capture_mode_intent() or nil
    local ui = get_ui()

    local rec = terminal.ensure(id)
    if not rec then
      return nil
    end

    local tab_id = state.get_tab_id(id)
    if not tab_id or not ui then
      remove_terminal_record(id)
      return nil
    end

    local ok_set, set_err = ui.set_active_tab(tab_id)
    if not ok_set then
      notify(("failed to select terminal %d: %s"):format(id, tostring(set_err)), vim.log.levels.ERROR)
      return nil
    end

    if type(ui.is_visible) == "function" and not ui.is_visible() and type(ui.show) == "function" then
      ui.show()
    end

    state.sync_current_from_ui()
    restore_mode_intent(rec, mode_intent)
    return rec
  end)
end

---@param id integer
---@return nil
function terminal.toggle(id)
  local ui = get_ui()
  if not ui or type(ui.toggle) ~= "function" then
    notify("qck ui is unavailable", vim.log.levels.ERROR)
    return
  end

  local rec = terminal.ensure(id)
  if not rec then
    return
  end

  local active_tab_id = ui_state.resolve_active_tab()
  if active_tab_id ~= state.get_tab_id(id) then
    terminal.open(id)
    return
  end

  ui.toggle()
  state.sync_current_from_ui()
end

---@param id integer
---@return nil
function terminal.delete(id)
  state.prune_stale()

  local rec = state.get_terminal(id)
  if not rec then
    notify(("terminal %d does not exist (no-op)"):format(id), vim.log.levels.WARN)
    return
  end

  local tab_id = state.get_tab_id(id)
  local ui = get_ui()
  if not tab_id or not ui or type(ui.delete_tab) ~= "function" then
    local rec_win = get_terminal_handle(rec)
    if rec_win then
      local ok_close, err = pcall(function() rec_win:close() end)
      if not ok_close then
        notify(("failed to delete terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
        return
      end
    end

    remove_terminal_record(id)
    return
  end

  local ok_delete, err = ui.delete_tab(tab_id)
  if not ok_delete then
    notify(("failed to delete terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
    return
  end

  state.sync_current_from_ui()
end

return terminal
