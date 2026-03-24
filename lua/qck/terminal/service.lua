-- Terminal-backed client primitives for the UI handoff migration.
--
-- UI now owns registered terminal-tab runtime behavior after a successful
-- `attach_and_show(...)` handoff. This module is limited to Snacks terminal
-- creation/reopen/delete helpers, preserved-mode handling, and terminal-buffer
-- mapping helpers that UI calls at the appropriate lifecycle points.
local state = require("qck.terminal.state")
local keymaps = require("qck.shared.keymaps")
local layout = require("qck.ui.layout")
local runtime = require("qck.ui.runtime")
local ui_state = require("qck.ui.state")
local notify = require("qck.shared.notify").notify

local terminal = {}

local UI_TERMINAL_CATEGORY = {
  key = "terminal",
  label = "T",
}

local snacks = nil
local user_mappings = {}
local mapping_lhs = {}
local previous_mapping_lhs = {}
local terminal_mapping_modes = { "n", "t" }

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

---@param rec qck.TerminalRecord|nil
---@return integer|nil
local function terminal_bufnr(rec)
  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    return nil
  end

  if type(rec_win.buf) == "number" and vim.api.nvim_buf_is_valid(rec_win.buf) then
    return rec_win.buf
  end

  if type(rec_win.buf) == "function" then
    local ok, bufnr = pcall(function() return rec_win:buf() end)
    if ok and type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
      return bufnr
    end
  end

  return nil
end

---@param rec qck.TerminalRecord|nil
---@return integer|nil
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
  local tab_id = state.get_tab_id(id)
  if tab_id then
    runtime.unregister_handle(tab_id)
    runtime.clear_owner_watchers(tab_id)
  end

  state.remove_terminal(id)
  state.update_current_after_removal(id)
end

---@param bufnr integer|nil
---@return nil
local function apply_user_mappings_to_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lhs_to_clear = keymaps.collect_lhs_to_clear(previous_mapping_lhs, mapping_lhs)

  for lhs in pairs(lhs_to_clear) do
    for _, mode in ipairs(terminal_mapping_modes) do
      pcall(vim.keymap.del, mode, lhs, { buffer = bufnr })
    end
  end

  for lhs, mapping in pairs(user_mappings) do
    local rhs = mapping
    local modes = terminal_mapping_modes
    if type(mapping) == "table" then
      rhs = mapping.rhs
      if type(mapping.terminal_modes) == "table" and #mapping.terminal_modes > 0 then
        modes = mapping.terminal_modes
      end
    end

    if type(rhs) == "function" or type(rhs) == "string" then
      for _, mode in ipairs(modes) do
        vim.keymap.set(mode, lhs, rhs, {
          buffer = bufnr,
          noremap = true,
          silent = true,
        })
      end
    end
  end
end

---@param handle any
---@return nil
function terminal.apply_user_mappings_to_handle(handle)
  if type(handle) ~= "table" then
    return
  end

  apply_user_mappings_to_buf(terminal_bufnr({ win = handle }))
end

---@param raw_mappings table|nil
---@return nil
function terminal.set_user_mappings(raw_mappings)
  previous_mapping_lhs, user_mappings, mapping_lhs = keymaps.update_state(mapping_lhs, raw_mappings)
end

---@return nil
function terminal.apply_user_mappings()
  for _, id in ipairs(state.live_ids()) do
    local rec = state.get_terminal(id)
    apply_user_mappings_to_buf(terminal_bufnr(rec))
  end
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

---@return nil
function terminal.refresh_current_layout()
  local ui = get_ui()
  if ui and type(ui.refresh_current_layout) == "function" then
    ui.refresh_current_layout()
  end
end

---@return integer|nil
function terminal.get_current_winid()
  local current_id = state.get_current_id()
  if not current_id then
    return nil
  end

  local rec = state.get_terminal(current_id)
  if not state.is_window_open(rec) then
    return nil
  end

  return terminal_winid(rec)
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
    ui.register_category(UI_TERMINAL_CATEGORY)
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

    if not runtime.is_visible() and type(ui.show) == "function" then
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

---@return nil
function terminal.hide_current_if_open()
  local ui = get_ui()
  if ui and type(ui.hide) == "function" then
    ui.hide()
  end
end

---@param id integer
---@return boolean
function terminal.move_up(id)
  local ui = get_ui()
  local tab_id = state.get_tab_id(id)
  if ui and tab_id and type(ui.move_tab) == "function" then
    return select(1, ui.move_tab(tab_id, -1))
  end

  return state.move_id(id, -1)
end

---@param id integer
---@return boolean
function terminal.move_down(id)
  local ui = get_ui()
  local tab_id = state.get_tab_id(id)
  if ui and tab_id and type(ui.move_tab) == "function" then
    return select(1, ui.move_tab(tab_id, 1))
  end

  return state.move_id(id, 1)
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
