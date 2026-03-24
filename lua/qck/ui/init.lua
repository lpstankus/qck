local layout = require("qck.ui.layout")
local runtime = require("qck.ui.runtime")
local state = require("qck.ui.state")
local tabbar = require("qck.ui.tabbar")
local autocmd = require("qck.shared.autocmd")
local notify = require("qck.shared.notify").notify
local terminal_service = require("qck.terminal.service")
local terminal_state = require("qck.terminal.state")

local ui = {}

local focus_cleanup_in_progress = false
local focus_leave_suppressed = 0
local resize_refresh_pending = false
local initialized = false

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
---@return qck.UiTabRecord|nil, integer|nil
local function get_tab_and_terminal_id(tab_id)
  local tab = state.get_tab(tab_id)
  if not tab then
    return nil, nil
  end

  return tab, terminal_state.get_id_by_terminal(tab.terminal)
end

---@param tab_id qck.UiTabId
---@param handle any
---@return nil
local function clear_owned_runtime(tab_id, handle)
  if runtime.get_handle_owner(handle) == tab_id then
    runtime.unregister_handle(tab_id)
  end
  clear_tab_watchers(tab_id)
end

---@return qck.UiTabId|nil
local function resolve_active_tab_id()
  local tab_id = state.resolve_active_tab()
  if not tab_id then
    runtime.clear_content_winid()
    tabbar.hide()
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

  clear_owned_runtime(tab_id, tab.terminal)
  state.delete_tab(tab_id)
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
    runtime.clear_content_winid()
    tabbar.hide()
  end
end

---@param tab_id qck.UiTabId
---@param handle any
---@return nil
local function handle_invalidated_tab(tab_id, handle)
  local _, terminal_id = get_tab_and_terminal_id(tab_id)

  if terminal_id then
    clear_tab_watchers(tab_id)
    terminal_service.handle_invalidation(terminal_id, handle)
    return
  end

  local was_active = resolve_active_tab_id() == tab_id
  clear_owned_runtime(tab_id, handle)
  state.delete_tab(tab_id)

  if not state.resolve_active_tab() then
    runtime.clear_content_winid()
    tabbar.hide()
    return
  end

  if was_active then
    runtime.clear_content_winid()
    tabbar.hide()
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

      clear_visible_watchers(tab_id)
      runtime.clear_content_winid()
      tabbar.hide()
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

  local tab, terminal_id = get_tab_and_terminal_id(tab_id)
  if not tab then
    return
  end

  if terminal_id then
    terminal_state.set_current_id(terminal_id)
    terminal_service.refresh_current_layout()
  else
    if not is_window_open(tab.terminal) then
      runtime.clear_content_winid()
      tabbar.hide()
      return
    end

    local ok_layout = select(1, apply_content_layout(tab.terminal))
    if not ok_layout then
      runtime.clear_content_winid()
      tabbar.hide()
      return
    end

    tabbar.show_for_terminal(tab.terminal)
  end

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
local function hide_other_visible_tabs(keep_tab_id)
  terminal_service.hide_current_if_open()

  for _, tab_id in ipairs(state.traversal_ids()) do
    if tab_id ~= keep_tab_id then
      clear_visible_watchers(tab_id)
      local tab = state.get_tab(tab_id)
      if tab and terminal_state.get_id_by_terminal(tab.terminal) == nil then
        hide_handle(tab.terminal)
      end
    end
  end
end

---@param tab_id qck.UiTabId
---@return boolean, string?
local function show_tab(tab_id)
  local tab, terminal_id = get_tab_and_terminal_id(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  if terminal_id then
    terminal_state.set_current_id(terminal_id)
    local rec = terminal_service.open(terminal_id)
    if not rec then
      return false, "failed to show active tab"
    end
    ensure_visible_watchers(tab_id, tab.terminal)
    return true
  end

  if not is_valid_handle(tab.terminal) then
    clear_owned_runtime(tab_id, tab.terminal)
    state.delete_tab(tab_id)
    return false, "tab handle is invalid"
  end

  clear_other_visible_watchers(tab_id)
  hide_other_visible_tabs(tab_id)

  local ok_show, show_err = show_handle(tab.terminal)
  if not ok_show then
    return false, show_err
  end

  local ok_layout, layout_err = apply_content_layout(tab.terminal)
  if not ok_layout then
    return false, layout_err
  end

  state.set_active_tab(tab_id)
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
local function delete_ui_owned_tab(tab_id)
  local tab = state.get_tab(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  local was_active = is_active_tab(tab_id)
  local was_visible = runtime.is_visible()

  clear_owned_runtime(tab_id, tab.terminal)
  close_handle(tab.terminal)

  local ok, err = state.delete_tab(tab_id)
  if not ok then
    return false, err
  end

  local next_active = state.resolve_active_tab()
  if not next_active then
    runtime.clear_content_winid()
    tabbar.hide()
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
---@return boolean, string?
local function delete_tab_internal(tab_id)
  local tab, terminal_id = get_tab_and_terminal_id(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  if terminal_id then
    terminal_service.delete(terminal_id)
    return true
  end

  return delete_ui_owned_tab(tab_id)
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
  if initialized then
    return
  end

  initialized = true
  install_global_watchers()
end

---@param tab_id qck.UiTabId
---@return nil
function ui.clear_watchers_for_tab(tab_id)
  clear_tab_watchers(tab_id)
end

---@param handle any
---@return nil
function ui.clear_visible_watchers_for_handle(handle)
  local tab = state.get_tab_by_terminal(handle)
  if not tab then
    return
  end

  clear_visible_watchers(tab.id)
end

---@param callback fun(): any
---@return any
function ui.with_suppressed_focus_leave(callback)
  if type(callback) ~= "function" then
    return nil
  end

  return with_suppressed_focus_leave(callback)
end

---@param handle any
---@return nil
function ui.ensure_tab_watchers_for_handle(handle)
  local tab = state.get_tab_by_terminal(handle)
  if not tab then
    return
  end

  ensure_buf_wipeout_watcher(tab.id, handle)

  if resolve_active_tab_id() ~= tab.id then
    clear_visible_watchers(tab.id)
    return
  end

  if is_window_open(handle) and runtime.get_tabbar_winid() ~= nil then
    runtime.set_content_winid(get_window_id(handle))
    ensure_visible_watchers(tab.id, handle)
    return
  end

  clear_visible_watchers(tab.id)
end

---@param category_key qck.UiCategoryKey
---@param handle any
---@return qck.UiTabId|nil, string?
function ui.attach_and_show(category_key, handle)
  prune_invalid_tabs()

  local previous_active = state.resolve_active_tab()
  local previous_visible = runtime.is_visible()

  local tab_id, err = state.register_tab(category_key, handle)
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

  clear_owned_runtime(tab_id, handle)
  state.delete_tab(tab_id)

  if previous_active then
    state.set_active_tab(previous_active)
  else
    state.set_active_tab_id(nil)
  end

  if previous_visible and previous_active then
    show_tab(previous_active)
  else
    runtime.clear_content_winid()
    tabbar.hide()
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

  local tab, terminal_id = get_tab_and_terminal_id(active_tab_id)
  if not tab then
    return
  end

  clear_visible_watchers(active_tab_id)

  if terminal_id then
    terminal_state.set_current_id(terminal_id)
    terminal_service.hide_current_if_open()
  else
    hide_handle(tab.terminal)
  end

  runtime.clear_content_winid()
  tabbar.hide()
end

---@return nil
function ui.toggle()
  prune_invalid_tabs()

  local tab_id = resolve_active_tab_id()
  if not tab_id then
    return
  end

  local tab, terminal_id = get_tab_and_terminal_id(tab_id)
  if not tab then
    return
  end

  if terminal_id then
    terminal_state.set_current_id(terminal_id)
    terminal_service.toggle(terminal_id)
    if not terminal_state.is_window_open(terminal_state.get_terminal(terminal_id)) then
      clear_visible_watchers(tab_id)
    end
    return
  end

  if is_window_open(tab.terminal) then
    clear_visible_watchers(tab_id)
    hide_handle(tab.terminal)
    runtime.clear_content_winid()
    tabbar.hide()
    return
  end

  show_tab(tab_id)
end

---@param tab_id qck.UiTabId
---@return boolean, string?
function ui.set_active_tab(tab_id)
  prune_invalid_tabs()

  local tab, terminal_id = get_tab_and_terminal_id(tab_id)
  if not tab then
    return false, "tab is not registered"
  end

  if terminal_id then
    terminal_state.set_current_id(terminal_id)
  else
    local ok, err = state.set_active_tab(tab_id)
    if not ok then
      return false, err
    end
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

  local _, terminal_id = get_tab_and_terminal_id(tab_id)
  if not state.get_tab(tab_id) then
    return false, "tab is not registered"
  end

  if terminal_id then
    if direction < 0 then
      terminal_service.move_up(terminal_id)
    else
      terminal_service.move_down(terminal_id)
    end
    return true
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

return ui
