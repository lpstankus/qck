-- Current pre-migration owner of terminal-backed qck UI behavior.
--
-- The written UI handoff contract lives in `plans/2-ui-handoff-contract.md`.
-- Until the later `lua/qck/ui/` migration lands, this module still owns the
-- runtime behavior that the contract will move behind UI: create-vs-reopen
-- behavior, preserved-mode handling, visible window swaps, terminal buffer
-- mapping application, and invalidation cleanup for terminal-backed tabs.
--
-- Target contract note: after a future successful `attach_and_show(...)`
-- handoff, UI becomes the sole runtime owner of the registered handle and this
-- module should stop calling raw handle methods during normal runtime flow.
local state = require("qck.terminal.state")
local tabbar = require("qck.terminal.tabbar")
local keymaps = require("qck.shared.keymaps")
local layout = require("qck.terminal.layout")
local runtime = require("qck.ui.runtime")
local notify = require("qck.shared.notify").notify

local terminal = {}

local snacks = nil
local user_mappings = {}
local mapping_lhs = {}
local previous_mapping_lhs = {}
local deleting_ids = {}
local terminal_mapping_modes = { "n", "t" }

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

---@param rec qck.TerminalRecord|nil
---@return boolean
local function apply_terminal_layout(rec)
  local winid = terminal_winid(rec)
  if not winid then
    runtime.clear_content_winid()
    return false
  end

  local shared_cfg = layout.build_shared_float_configs(winid)
  if not shared_cfg then
    return false
  end

  local ok, err = pcall(vim.api.nvim_win_set_config, winid, shared_cfg.terminal)
  if not ok then
    notify(("failed to update terminal layout: %s"):format(tostring(err)), vim.log.levels.ERROR)
    return false
  end

  runtime.set_content_winid(winid)
  return true
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

---@param id integer
---@return nil
local function purge_terminal_record(id)
  runtime.unregister_handle(id)
  runtime.clear_owner_watchers(id)
  state.remove_terminal(id)
end

---@param id integer
---@return nil
local function remove_terminal_record(id)
  purge_terminal_record(id)
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
local function sync_tabbar_for_current()
  local current_id = state.get_current_id()
  if not current_id then
    tabbar.hide()
    return
  end

  local current_rec = state.get_terminal(current_id)
  if not state.is_window_open(current_rec) then
    tabbar.hide()
    return
  end

  tabbar.sync(current_rec, current_id)
end

---@return nil
function terminal.refresh_current_layout()
  local current_id = state.get_current_id()
  if not current_id then
    runtime.clear_content_winid()
    tabbar.hide()
    return
  end

  local current_rec = state.get_terminal(current_id)
  if not state.is_window_open(current_rec) then
    runtime.clear_content_winid()
    tabbar.hide()
    return
  end

  apply_terminal_layout(current_rec)
  tabbar.sync(current_rec, current_id)
end

---@param id integer
---@return nil
local function hide_window_if_open(id)
  local rec = state.get_terminal(id)
  if not state.is_window_open(rec) then
    if state.get_current_id() == id then
      runtime.clear_content_winid()
    end
    return
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    return
  end

  local ok_hide, err = pcall(function() rec_win:toggle() end)
  if not ok_hide then
    notify(("failed to hide terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
    return
  end

  if state.get_current_id() == id then
    runtime.clear_content_winid()
  end
end

---@param target_id integer
---@return integer|nil
local function get_previous_visible_id(target_id)
  local current_id = state.get_current_id()
  if current_id and current_id ~= target_id then
    local current_rec = state.get_terminal(current_id)
    if state.is_window_open(current_rec) then
      return current_id
    end
  end

  for _, live_id in ipairs(state.ordered_ids()) do
    if live_id ~= target_id then
      local rec = state.get_terminal(live_id)
      if state.is_window_open(rec) then
        return live_id
      end
    end
  end

  return nil
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
  preserve_mode = preserve_mode == true
  local previous_visible_id = get_previous_visible_id(id)
  local mode_intent = preserve_mode and capture_mode_intent() or nil

  if not snacks or not ensure_snacks() then return nil end

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
  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    safe_close_handle(term_or_err)
    notify(("failed to initialize terminal %d handle"):format(id), vim.log.levels.ERROR)
    return nil
  end

  state.set_terminal(id, rec)
  runtime.register_handle(id, rec_win)
  runtime.set_owner_watchers(id, { buf_wipeout = true })
  apply_terminal_layout(rec)
  if previous_visible_id then
    hide_window_if_open(previous_visible_id)
  end
  state.set_current_id(id)
  apply_user_mappings_to_buf(terminal_bufnr(rec))
  tabbar.sync(rec, id)
  restore_mode_intent(rec, mode_intent)

  if type(rec_win.on) == "function" then
    rec_win:on("BufWipeout", function()
      if deleting_ids[id] then
        return
      end
      if state.get_terminal(id) == rec then
        remove_terminal_record(id)
        sync_tabbar_for_current()
      end
    end, { buf = true })
  end

  return rec
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
  preserve_mode = preserve_mode == true
  local previous_visible_id = get_previous_visible_id(id)
  local mode_intent = preserve_mode and capture_mode_intent() or nil

  local rec = terminal.ensure(id)
  if not rec then
    return nil
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    remove_terminal_record(id)
    return nil
  end

  if previous_visible_id then
    hide_window_if_open(previous_visible_id)
  end

  if not state.is_window_open(rec) then
    local ok_show, err = pcall(function() rec_win:show() end)
    if not ok_show then
      notify(("failed to open terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
      return nil
    end
  end

  apply_terminal_layout(rec)

  state.set_current_id(id)
  tabbar.sync(rec, id)
  restore_mode_intent(rec, mode_intent)
  return rec
end

---@param id integer
---@return nil
function terminal.close_if_open(id)
  state.prune_stale()

  local rec = state.get_terminal(id)
  if not rec then
    notify(("terminal %d does not exist (no-op)"):format(id), vim.log.levels.WARN)
    return
  end

  if not state.is_window_open(rec) then
    notify(("terminal %d window is closed (no-op)"):format(id), vim.log.levels.WARN)
    return
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    notify(("terminal %d has an invalid handle (no-op)"):format(id), vim.log.levels.WARN)
    return
  end

  local ok_close, err = pcall(function() rec_win:close() end)
  if not ok_close then
    notify(("failed to close terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
    return
  end

  remove_terminal_record(id)
  sync_tabbar_for_current()
end

---@param id integer
---@return nil
function terminal.toggle(id)
  local rec = terminal.ensure(id)
  if not rec then
    return
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    remove_terminal_record(id)
    return
  end

  local ok_toggle, err = pcall(function() rec_win:toggle() end)
  if not ok_toggle then
    notify(("failed to toggle terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
    return
  end

  state.set_current_id(id)
  if state.is_window_open(rec) then
    apply_terminal_layout(rec)
    tabbar.sync(rec, id)
  else
    runtime.clear_content_winid()
    tabbar.hide()
  end
end

---@return nil
function terminal.hide_current_if_open()
  local current_id = state.get_current_id()
  if not current_id then
    return
  end

  hide_window_if_open(current_id)
end

---@param id integer
---@return boolean
function terminal.move_up(id)
  local moved = state.move_id(id, -1)
  if not moved then
    return false
  end

  sync_tabbar_for_current()
  return true
end

---@param id integer
---@return boolean
function terminal.move_down(id)
  local moved = state.move_id(id, 1)
  if not moved then
    return false
  end

  sync_tabbar_for_current()
  return true
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

  local ids = state.ordered_ids()
  local next_id = nil
  for i, live_id in ipairs(ids) do
    if live_id == id and #ids > 1 then
      local next_idx = i < #ids and i + 1 or i - 1
      next_id = ids[next_idx]
      break
    end
  end

  local removed_current = state.get_current_id() == id
  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    purge_terminal_record(id)
    sync_tabbar_for_current()
    return
  end

  deleting_ids[id] = true
  local ok_close, err = pcall(function() rec_win:close() end)
  deleting_ids[id] = nil
  if not ok_close then
    notify(("failed to delete terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
    return
  end

  purge_terminal_record(id)

  if not removed_current then
    sync_tabbar_for_current()
    return
  end

  state.set_current_id(nil)
  if next_id then
    terminal.open(next_id)
  else
    tabbar.hide()
  end
end

return terminal
