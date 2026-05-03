local layout = require("qck.ui.layout")
local runtime = require("qck.ui.runtime")
local state = require("qck.ui.state")
local tabbar = require("qck.ui.tabbar")
local autocmd = require("qck.shared.autocmd")
local keymaps = require("qck.shared.keymaps")
local notify = require("qck.shared.notify").notify

local ui = {}

local focus_cleanup_in_progress = false
local focus_leave_suppressed = 0
local resize_refresh_pending = false
local initialized = false
local show_tab
local user_terminal_mappings = {}
local terminal_mapping_lhs = {}
local previous_terminal_mapping_lhs = {}
local terminal_mapping_modes = { "n", "t" }
local UI_TASK_CATEGORY = {
  key = "task",
  label = "K",
}
local UI_TERMINAL_CATEGORY = {
  key = "terminal",
  label = "T",
}

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

  return is_normal_mode(mode_info.mode) and "normal" or nil
end

---@param callback fun(): any
---@return any
local function with_suppressed_focus_leave(callback)
  focus_leave_suppressed = focus_leave_suppressed + 1

  local ok, result = pcall(callback)

  focus_leave_suppressed = math.max(0, focus_leave_suppressed - 1)

  if not ok then
    error(result)
  end

  return result
end

---@param handle any
---@return boolean
local function is_valid_handle(handle)
  if type(handle) ~= "table" or type(handle.buf_valid) ~= "function" then
    return false
  end

  local ok, valid = pcall(function() return handle:buf_valid() end)
  return ok and valid == true
end

---@param handle any
---@return boolean
local function is_window_open(handle)
  if type(handle) ~= "table" or type(handle.valid) ~= "function" then
    return false
  end

  local ok, valid = pcall(function() return handle:valid() end)
  return ok and valid == true
end

---@param handle any
---@return integer|nil
local function get_window_id(handle)
  if not is_window_open(handle) then
    return nil
  end

  if type(handle.win) == "number" and vim.api.nvim_win_is_valid(handle.win) then
    return handle.win
  end

  if type(handle.win) == "function" then
    local ok, winid = pcall(function() return handle:win() end)
    if ok and type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
      return winid
    end
  end

  return nil
end

---@param handle any
---@return boolean, string?
local function apply_content_layout(handle)
  local winid = get_window_id(handle)
  if not winid then
    runtime.clear_content_winid()
    return false, "tab window is unavailable"
  end

  local shared = layout.build_shared_float_configs(winid)
  if not shared then
    return false, "failed to build tab layout"
  end

  local ok, err = pcall(vim.api.nvim_win_set_config, winid, shared.terminal)
  if not ok then
    return false, tostring(err)
  end

  runtime.set_content_winid(winid)
  return true
end

---@param handle any
---@return boolean, string?
local function show_handle(handle)
  if not is_valid_handle(handle) then
    return false, "tab handle is invalid"
  end

  if is_window_open(handle) then
    return true
  end

  if type(handle.show) ~= "function" then
    return false, "tab handle cannot be shown"
  end

  local ok, err = pcall(function() handle:show() end)
  if not ok then
    return false, tostring(err)
  end

  return true
end

---@param handle any
---@return boolean, string?
local function hide_handle(handle)
  if not is_window_open(handle) then
    return true
  end

  if type(handle.toggle) ~= "function" then
    return false, "tab handle cannot be hidden"
  end

  local ok, err = pcall(function() handle:toggle() end)
  if not ok then
    return false, tostring(err)
  end

  return true
end

---@param handle any
---@return boolean
local function close_handle(handle)
  if type(handle) ~= "table" or type(handle.close) ~= "function" then
    return false
  end

  return pcall(function() handle:close() end)
end

---@param handle any
---@return integer|nil
local function get_buffer_id(handle)
  if not is_valid_handle(handle) then
    return nil
  end

  if type(handle.buf) == "number" and vim.api.nvim_buf_is_valid(handle.buf) then
    return handle.buf
  end

  if type(handle.buf) == "function" then
    local ok, bufnr = pcall(function() return handle:buf() end)
    if ok and type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
      return bufnr
    end
  end

  return nil
end

---@param tab_id qck.UiTabId
---@return qck.UiRuntimeWatchers
local function get_tab_watchers(tab_id)
  return runtime.get_owner_watchers(tab_id)
end

---@param tab_id qck.UiTabId
---@param watchers qck.UiRuntimeWatchers
---@return nil
local function set_tab_watchers(tab_id, watchers)
  runtime.set_owner_watchers(tab_id, watchers)
end

---@param tab_id qck.UiTabId
---@return nil
local function clear_tab_watchers(tab_id)
  local watchers = get_tab_watchers(tab_id)
  autocmd.delete(watchers.buf_wipeout_autocmd_id)
  autocmd.delete(watchers.content_close_autocmd_id)
  autocmd.delete(watchers.tabbar_close_autocmd_id)
  runtime.clear_owner_watchers(tab_id)
end

---@param tab_id qck.UiTabId
---@return nil
local function clear_visible_watchers(tab_id)
  local watchers = get_tab_watchers(tab_id)
  autocmd.delete(watchers.content_close_autocmd_id)
  autocmd.delete(watchers.tabbar_close_autocmd_id)
  watchers.content_close_autocmd_id = nil
  watchers.watched_content_win = nil
  watchers.tabbar_close_autocmd_id = nil
  watchers.watched_tabbar_win = nil
  watchers.suppress_tabbar_close_action = false
  set_tab_watchers(tab_id, watchers)
end

---@param keep_tab_id qck.UiTabId|nil
---@return nil
local function clear_other_visible_watchers(keep_tab_id)
  for _, tab_id in ipairs(state.traversal_ids()) do
    if tab_id ~= keep_tab_id then
      clear_visible_watchers(tab_id)
    end
  end
end

---@param tab_id qck.UiTabId
---@return nil
local function clear_owned_runtime(tab_id)
  runtime.unregister_handle(tab_id)
  clear_tab_watchers(tab_id)
end

---@param mapping any
---@return string[]
local function get_terminal_mapping_modes(mapping)
  return type(mapping) == "table" and type(mapping.terminal_modes) == "table" and #mapping.terminal_modes > 0
      and mapping.terminal_modes
    or terminal_mapping_modes
end

---@param handle any
---@return nil
local function apply_terminal_mappings(handle)
  local buf = get_buffer_id(handle)
  keymaps.apply_to_buffer(
    buf,
    previous_terminal_mapping_lhs,
    terminal_mapping_lhs,
    user_terminal_mappings,
    terminal_mapping_modes,
    get_terminal_mapping_modes
  )

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local function handle_mouse_release()
    tabbar.handle_left_click(vim.fn.getmousepos())
  end

  vim.keymap.set("n", "<LeftRelease>", handle_mouse_release, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("t", "<LeftRelease>", handle_mouse_release, { buffer = buf, noremap = true, silent = true })
end

---@param handle any
---@return nil
local function clear_terminal_mappings(handle)
  local buf = get_buffer_id(handle)
  keymaps.apply_to_buffer(buf, previous_terminal_mapping_lhs, terminal_mapping_lhs, nil, terminal_mapping_modes)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  pcall(vim.keymap.del, "n", "<LeftRelease>", { buffer = buf })
  pcall(vim.keymap.del, "t", "<LeftRelease>", { buffer = buf })
end

---@param tab_id qck.UiTabId|nil
---@return nil
local function restore_active_selection(tab_id)
  if tab_id then
    state.set_active_tab(tab_id)
  else
    state.set_active_tab_id(nil)
  end
end

---@return nil
local function clear_visible_ui()
  runtime.clear_content_winid()
  tabbar.hide()
end

---@param handle any
---@param mode_intent "normal"|nil
---@return nil
local function restore_mode_intent(handle, mode_intent)
  if mode_intent ~= "normal" then
    return
  end

  local winid = get_window_id(handle)
  if not winid then
    return
  end

  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.cmd, "stopinsert")
end

---@param tab_id qck.UiTabId
---@param handle any
---@return nil
local function hide_visible_tab(tab_id, handle)
  clear_visible_watchers(tab_id)
  hide_handle(handle)
  clear_visible_ui()
end

---@param tab_id qck.UiTabId
---@return nil
local function detach_tab(tab_id)
  clear_owned_runtime(tab_id)
  state.delete_tab(tab_id)
end

---@param tab_id qck.UiTabId
---@param handle any
---@param previous_active qck.UiTabId|nil
---@param previous_visible boolean
---@param handle_was_visible boolean
---@param handle_win_config table|nil
---@return string|nil
local function rollback_failed_attach(tab_id, handle, previous_active, previous_visible, handle_was_visible, handle_win_config)
  clear_owned_runtime(tab_id)
  clear_terminal_mappings(handle)
  clear_visible_ui()

  if handle_was_visible then
    local winid = get_window_id(handle)
    if winid and type(handle_win_config) == "table" then
      pcall(vim.api.nvim_win_set_config, winid, vim.deepcopy(handle_win_config))
    end
  else
    hide_handle(handle)
  end

  pcall(state.delete_tab, tab_id)
  restore_active_selection(previous_active)

  if not (previous_visible and previous_active) then
    return nil
  end

  local ok_restore, restore_err = pcall(function()
    local ok_show, err = show_tab(previous_active)
    if not ok_show then
      error(err)
    end
  end)

  if ok_restore then
    return nil
  end

  clear_visible_ui()
  return tostring(restore_err)
end

---@return qck.UiTabId|nil
local function resolve_active_tab_id()
  local tab_id = state.resolve_active_tab()
  if not tab_id then
    clear_visible_ui()
  end
  return tab_id
end

---@param tab_id qck.UiTabId
---@return boolean
local function prune_invalid_tab(tab_id)
  local tab = state.get_tab(tab_id)
  if not tab then
    return false
  end

  if is_valid_handle(tab.terminal) then
    return false
  end

  detach_tab(tab_id)
  return true
end

---@return nil
local function prune_invalid_tabs()
  local removed = false

  for _, tab_id in ipairs(state.traversal_ids()) do
    if prune_invalid_tab(tab_id) then
      removed = true
    end
  end

  if removed and not state.resolve_active_tab() then
    clear_visible_ui()
  end
end

---@param tab_id qck.UiTabId
---@param handle any
---@return nil
local function handle_invalidated_tab(tab_id, handle)
  local was_active = resolve_active_tab_id() == tab_id
  detach_tab(tab_id)

  if not state.resolve_active_tab() then
    clear_visible_ui()
    return
  end

  if was_active then
    clear_visible_ui()
    return
  end

  if runtime.is_visible() then
    tabbar.render()
  end
end

---@param tab_id qck.UiTabId
---@param handle any
---@return nil
local function ensure_buf_wipeout_watcher(tab_id, handle)
  local bufnr = get_buffer_id(handle)
  if not bufnr then
    return
  end

  local watchers = get_tab_watchers(tab_id)
  if watchers.watched_bufnr == bufnr and watchers.buf_wipeout_autocmd_id ~= nil then
    return
  end

  autocmd.delete(watchers.buf_wipeout_autocmd_id)
  watchers.buf_wipeout_autocmd_id = nil
  watchers.watched_bufnr = bufnr
  set_tab_watchers(tab_id, watchers)

  local autocmd_id = autocmd.create("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      local active_watchers = get_tab_watchers(tab_id)
      active_watchers.buf_wipeout_autocmd_id = nil
      active_watchers.watched_bufnr = nil
      set_tab_watchers(tab_id, active_watchers)

      local tab = state.get_tab(tab_id)
      if not tab or tab.terminal ~= handle then
        return
      end

      handle_invalidated_tab(tab_id, handle)
    end,
  })

  watchers = get_tab_watchers(tab_id)
  watchers.buf_wipeout_autocmd_id = autocmd_id
  set_tab_watchers(tab_id, watchers)
end

---@param tab_id qck.UiTabId
---@param handle any
---@return nil
local function ensure_content_close_watcher(tab_id, handle)
  local winid = get_window_id(handle)
  if not winid then
    clear_visible_watchers(tab_id)
    return
  end

  local watchers = get_tab_watchers(tab_id)
  if watchers.watched_content_win == winid and watchers.content_close_autocmd_id ~= nil then
    return
  end

  autocmd.delete(watchers.content_close_autocmd_id)
  watchers.content_close_autocmd_id = nil
  watchers.watched_content_win = winid
  set_tab_watchers(tab_id, watchers)

  local autocmd_id = autocmd.create("WinClosed", {
    pattern = tostring(winid),
    once = true,
    callback = function()
      local active_watchers = get_tab_watchers(tab_id)
      active_watchers.content_close_autocmd_id = nil
      active_watchers.watched_content_win = nil
      set_tab_watchers(tab_id, active_watchers)

      local tab = state.get_tab(tab_id)
      if not tab or tab.terminal ~= handle then
        return
      end

      if not is_valid_handle(handle) then
        handle_invalidated_tab(tab_id, handle)
        return
      end

      hide_visible_tab(tab_id, handle)
    end,
  })

  watchers = get_tab_watchers(tab_id)
  watchers.content_close_autocmd_id = autocmd_id
  set_tab_watchers(tab_id, watchers)
end

---@param tab_id qck.UiTabId
---@return nil
local function ensure_tabbar_close_watcher(tab_id)
  local winid = runtime.get_tabbar_winid()
  if not winid then
    clear_visible_watchers(tab_id)
    return
  end

  local watchers = get_tab_watchers(tab_id)
  if watchers.watched_tabbar_win == winid and watchers.tabbar_close_autocmd_id ~= nil then
    return
  end

  autocmd.delete(watchers.tabbar_close_autocmd_id)
  watchers.tabbar_close_autocmd_id = nil
  watchers.watched_tabbar_win = winid
  set_tab_watchers(tab_id, watchers)

  local autocmd_id = autocmd.create("WinClosed", {
    pattern = tostring(winid),
    once = true,
    callback = function()
      local active_watchers = get_tab_watchers(tab_id)
      active_watchers.tabbar_close_autocmd_id = nil
      active_watchers.watched_tabbar_win = nil
      set_tab_watchers(tab_id, active_watchers)

      if active_watchers.suppress_tabbar_close_action then
        active_watchers.suppress_tabbar_close_action = false
        set_tab_watchers(tab_id, active_watchers)
        return
      end

      local ok_hide, err = pcall(ui.hide)
      if not ok_hide then
        notify(("failed to hide qck ui after tabbar close: %s"):format(tostring(err)), vim.log.levels.ERROR)
      end
    end,
  })

  watchers = get_tab_watchers(tab_id)
  watchers.tabbar_close_autocmd_id = autocmd_id
  set_tab_watchers(tab_id, watchers)
end

---@param tab_id qck.UiTabId
---@param handle any
---@return nil
local function ensure_visible_watchers(tab_id, handle)
  clear_other_visible_watchers(tab_id)
  ensure_content_close_watcher(tab_id, handle)
  ensure_tabbar_close_watcher(tab_id)
end

---@return nil
local function refresh_current_layout()
  prune_invalid_tabs()

  local tab_id = resolve_active_tab_id()
  if not tab_id then
    return
  end

  local tab = state.get_tab(tab_id)
  if not tab then
    return
  end

  if not is_window_open(tab.terminal) then
    clear_visible_ui()
    return
  end

  local ok_layout = select(1, apply_content_layout(tab.terminal))
  if not ok_layout then
    clear_visible_ui()
    return
  end

  apply_terminal_mappings(tab.terminal)
  tabbar.show_for_terminal(tab.terminal)

  ensure_visible_watchers(tab_id, tab.terminal)
end

---@return nil
local function install_global_watchers()
  local watchers = runtime.get_global_watchers()

  if watchers.focus_leave_autocmd_id == nil then
    watchers.focus_leave_autocmd_id = autocmd.create({ "WinEnter", "BufEnter", "TabEnter" }, {
      callback = function()
        if focus_cleanup_in_progress then
          return
        end

        if focus_leave_suppressed > 0 then
          return
        end

        local content_win = runtime.get_content_winid()
        local tabbar_win = runtime.get_tabbar_winid()
        if not content_win and not tabbar_win then
          return
        end

        local current_win = vim.api.nvim_get_current_win()
        if (content_win and current_win == content_win) or (tabbar_win and current_win == tabbar_win) then
          return
        end

        focus_cleanup_in_progress = true
        local ok_hide, err = pcall(ui.hide)

        vim.schedule(function()
          focus_cleanup_in_progress = false
        end)

        if not ok_hide then
          notify(("failed to hide qck ui after focus left qck windows: %s"):format(tostring(err)), vim.log.levels.ERROR)
        end
      end,
    })
  end

  if watchers.resize_autocmd_id == nil then
    watchers.resize_autocmd_id = autocmd.create("VimResized", {
      callback = function()
        if resize_refresh_pending then
          return
        end

        resize_refresh_pending = true
        vim.schedule(function()
          resize_refresh_pending = false
          refresh_current_layout()
        end)
      end,
    })
  end

  runtime.set_global_watchers(watchers)
end

---@param keep_tab_id qck.UiTabId
---@return nil
local function hide_other_tabs(keep_tab_id)
  for _, tab_id in ipairs(state.traversal_ids()) do
    if tab_id ~= keep_tab_id then
      clear_visible_watchers(tab_id)
      local tab = state.get_tab(tab_id)
      if tab then
        hide_handle(tab.terminal)
      end
    end
  end
end

---@param tab_id qck.UiTabId
---@return boolean, string?
show_tab = function(tab_id)
  local tab = state.get_tab(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  if not is_valid_handle(tab.terminal) then
    detach_tab(tab_id)
    return false, "tab handle is invalid"
  end

  hide_other_tabs(tab_id)

  local ok_show, show_err = show_handle(tab.terminal)
  if not ok_show then
    return false, show_err
  end

  local ok_layout, layout_err = apply_content_layout(tab.terminal)
  if not ok_layout then
    return false, layout_err
  end

  state.set_active_tab(tab_id)
  apply_terminal_mappings(tab.terminal)
  tabbar.show_for_terminal(tab.terminal)
  ensure_visible_watchers(tab_id, tab.terminal)
  return true
end

---@param tab_id qck.UiTabId
---@return boolean
local function is_active_tab(tab_id)
  return resolve_active_tab_id() == tab_id
end

---@param tab_id qck.UiTabId
---@return boolean, string?
local function delete_tab_internal(tab_id)
  local tab = state.get_tab(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  local was_active = is_active_tab(tab_id)
  local was_visible = runtime.is_visible()

  clear_owned_runtime(tab_id)
  close_handle(tab.terminal)
  local ok, err = state.delete_tab(tab_id)
  if not ok then
    return false, err
  end

  local next_active = state.resolve_active_tab()
  if not next_active then
    clear_visible_ui()
    return true
  end

  if was_visible and was_active then
    return show_tab(next_active)
  end

  if runtime.is_visible() then
    tabbar.render()
  end

  return true
end

---@param tab_id qck.UiTabId
---@param direction integer
---@return boolean, string?
local function move_ui_owned_tab(tab_id, direction)
  local tab = state.get_tab(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  state.move_tab(tab_id, direction)
  if runtime.is_visible() then
    tabbar.render()
  end
  return true
end

---@param spec qck.UiCategorySpec
---@return boolean, string?
function ui.register_category(spec)
  return state.register_category(spec)
end

---@return nil
function ui.setup()
  state.register_category(UI_TASK_CATEGORY)
  state.register_category(UI_TERMINAL_CATEGORY)

  if initialized then
    return
  end

  initialized = true
  install_global_watchers()
end

---@return boolean
function ui.is_visible()
  return runtime.is_visible()
end

---@return boolean
function ui.open_active()
  prune_invalid_tabs()

  if not resolve_active_tab_id() then
    return false
  end

  ui.show()
  return true
end

---@return boolean
function ui.toggle_active()
  prune_invalid_tabs()

  if not resolve_active_tab_id() then
    return false
  end

  ui.toggle()
  return true
end

---@return boolean, string?
function ui.close_active()
  prune_invalid_tabs()

  local tab_id = resolve_active_tab_id()
  if not tab_id then
    return false, "no active tab"
  end

  return delete_tab_internal(tab_id)
end

---@param direction integer
---@return nil
function ui.cycle(direction)
  with_suppressed_focus_leave(function()
    local target_tab_id = state.get_cycle_tab_id(direction)
    if not target_tab_id then
      return
    end

    local mode_intent = capture_mode_intent()
    local ok, err = ui.set_active_tab(target_tab_id)
    if not ok then
      notify(("failed to select terminal: %s"):format(tostring(err)), vim.log.levels.ERROR)
      return
    end

    if not runtime.is_visible() then
      ui.show()
    end

    local tab = state.get_tab(target_tab_id)
    if tab then
      restore_mode_intent(tab.terminal, mode_intent)
    end
  end)
end

---@param raw_mappings table|nil
---@return nil
function ui.set_terminal_user_mappings(raw_mappings)
  previous_terminal_mapping_lhs, user_terminal_mappings, terminal_mapping_lhs = keymaps.update_state(
    terminal_mapping_lhs,
    raw_mappings
  )
end

---@return nil
function ui.apply_terminal_user_mappings()
  for _, tab_id in ipairs(state.traversal_ids()) do
    local tab = state.get_tab(tab_id)
    if tab then
      apply_terminal_mappings(tab.terminal)
    end
  end
end

---@param callback fun(): any
---@return any
function ui.with_suppressed_focus_leave(callback)
  if type(callback) ~= "function" then
    return nil
  end

  return with_suppressed_focus_leave(callback)
end

---@param category_key qck.UiCategoryKey
---@param handle any
---@param opts? qck.UiRegisterTabOpts
---@return qck.UiTabId|nil, string?
function ui.attach_and_show(category_key, handle, opts)
  prune_invalid_tabs()

  local previous_active = state.resolve_active_tab()
  local previous_visible = runtime.is_visible()
  local handle_was_visible = is_window_open(handle)
  local handle_win_config = nil
  if handle_was_visible then
    local handle_winid = get_window_id(handle)
    if handle_winid then
      handle_win_config = vim.api.nvim_win_get_config(handle_winid)
    end
  end

  local tab_id, err = state.register_tab(category_key, handle, opts)
  if not tab_id then
    return nil, err
  end

  local committed = false
  local ok, show_err = pcall(function()
    local ok_register, register_err = runtime.register_handle(tab_id, handle)
    if not ok_register then
      error(register_err)
    end

    runtime.set_owner_watchers(tab_id, {})
    ensure_buf_wipeout_watcher(tab_id, handle)

    local ok_active, active_err = state.set_active_tab(tab_id)
    if not ok_active then
      error(active_err)
    end

    local ok_show, inner_show_err = show_tab(tab_id)
    if not ok_show then
      error(inner_show_err)
    end

    committed = true
  end)

  if committed and ok then
    return tab_id, nil
  end

  local rollback_err = rollback_failed_attach(
    tab_id,
    handle,
    previous_active,
    previous_visible,
    handle_was_visible,
    handle_win_config
  )
  if rollback_err then
    return nil, ("%s (rollback failed: %s)"):format(tostring(show_err), rollback_err)
  end

  return nil, show_err
end

---@return nil
function ui.show()
  prune_invalid_tabs()

  local tab_id = resolve_active_tab_id()
  if not tab_id then
    return
  end

  show_tab(tab_id)
end

---@return nil
function ui.hide()
  prune_invalid_tabs()

  local active_tab_id = resolve_active_tab_id()
  if not active_tab_id then
    return
  end

  local tab = state.get_tab(active_tab_id)
  if not tab then
    return
  end

  hide_visible_tab(active_tab_id, tab.terminal)
end

---@return nil
function ui.toggle()
  prune_invalid_tabs()

  local tab_id = resolve_active_tab_id()
  if not tab_id then
    return
  end

  local tab = state.get_tab(tab_id)
  if not tab then
    return
  end

  if is_window_open(tab.terminal) then
    hide_visible_tab(tab_id, tab.terminal)
    return
  end

  show_tab(tab_id)
end

---@param tab_id qck.UiTabId
---@return boolean, string?
function ui.set_active_tab(tab_id)
  prune_invalid_tabs()

  local tab = state.get_tab(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  local ok, err = state.set_active_tab(tab_id)
  if not ok then
    return false, err
  end

  if runtime.is_visible() then
    return show_tab(tab_id)
  end

  return true
end

---@param tab_id qck.UiTabId
---@return boolean, string?
function ui.delete_tab(tab_id)
  prune_invalid_tabs()
  return delete_tab_internal(tab_id)
end

---@param tab_id qck.UiTabId
---@param direction integer
---@return boolean, string?
function ui.move_tab(tab_id, direction)
  prune_invalid_tabs()

  if direction ~= -1 and direction ~= 1 then
    return false, "direction must be -1 or 1"
  end

  if not state.get_tab(tab_id) then
    return false, "tab is not registered"
  end

  return move_ui_owned_tab(tab_id, direction)
end

---@return nil
function ui.toggle_tabbar_focus()
  local tabbar_win = runtime.get_tabbar_winid()
  local content_win = runtime.get_content_winid()
  local current_win = vim.api.nvim_get_current_win()

  if tabbar_win and current_win == tabbar_win then
    if content_win then
      vim.api.nvim_set_current_win(content_win)
    end
    return
  end

  if content_win and current_win == content_win then
    if tabbar_win then
      vim.api.nvim_set_current_win(tabbar_win)
    end
    return
  end

  if content_win then
    vim.api.nvim_set_current_win(content_win)
    return
  end

  if tabbar_win then
    vim.api.nvim_set_current_win(tabbar_win)
  end
end

---@return nil
function ui.refresh_current_layout()
  refresh_current_layout()
end

---@return nil
function ui.prune_invalid_tabs()
  prune_invalid_tabs()
end

return ui
