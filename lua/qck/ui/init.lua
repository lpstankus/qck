local layout = require("qck.ui.layout")
local runtime = require("qck.ui.runtime")
local state = require("qck.ui.state")
local tabbar = require("qck.ui.tabbar")
local terminal_service = require("qck.terminal.service")
local terminal_state = require("qck.terminal.state")

local ui = {}

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
  runtime.clear_owner_watchers(tab_id)
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

---@param keep_tab_id qck.UiTabId
---@return nil
local function hide_other_visible_tabs(keep_tab_id)
  terminal_service.hide_current_if_open()

  for _, tab_id in ipairs(state.traversal_ids()) do
    if tab_id ~= keep_tab_id then
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
    return true
  end

  if not is_valid_handle(tab.terminal) then
    clear_owned_runtime(tab_id, tab.terminal)
    state.delete_tab(tab_id)
    return false, "tab handle is invalid"
  end

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

  close_handle(tab.terminal)
  clear_owned_runtime(tab_id, tab.terminal)

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
    return
  end

  if is_window_open(tab.terminal) then
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

return ui
