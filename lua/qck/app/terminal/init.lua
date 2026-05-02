local layout = require("qck.ui.layout")
local ui = require("qck.ui")
local ui_state = require("qck.ui.state")
local terminal_service = require("qck.app.terminal.service")
local notify = require("qck.shared.notify").notify

local terminal = {}

local UI_TERMINAL_CATEGORY_KEY = "terminal"
local UI_TASK_CATEGORY_KEY = "task"
local UI_TASK_CATEGORY = {
  key = UI_TASK_CATEGORY_KEY,
  label = "K",
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

---@param handle any
---@return integer|nil
local function get_window_id(handle)
  if type(handle) ~= "table" then
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

---@param handle any
---@return nil
local function focus_terminal(handle)
  local winid = get_window_id(handle)
  if not winid then
    return
  end

  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.cmd, "startinsert")
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

---@param cmd qck.Command
---@return string
local function task_command_key(cmd)
  if type(cmd) == "string" then
    return "s:" .. cmd
  end

  return "l:" .. vim.json.encode(cmd)
end

---@param key string
---@return qck.UiTabRecord|nil
local function find_task_tab_by_key(key)
  for _, tab_id in ipairs(ui_state.traversal_ids()) do
    local tab = ui_state.get_tab(tab_id)
    local handle = tab and tab.terminal or nil
    if tab
      and tab.category_key == UI_TASK_CATEGORY_KEY
      and type(handle) == "table"
      and handle.qck_task_command_key == key
      and is_valid_handle(handle)
    then
      return tab
    end
  end

  return nil
end

---@param tab qck.UiTabRecord
---@return qck.UiTabRecord|nil
local function show_existing_task_tab(tab)
  return ui.with_suppressed_focus_leave(function()
    local ok, err = ui.set_active_tab(tab.id)
    if not ok then
      notify(err or "failed to select task terminal", vim.log.levels.ERROR)
      return nil
    end

    if not ui.is_visible() then
      ui.show()
    end

    local selected = ui_state.get_tab(tab.id)
    if selected then
      focus_terminal(selected.terminal)
    end
    return selected
  end)
end

---@param cmd qck.Command|nil
---@param category_key qck.UiCategoryKey
---@param auto_close boolean
---@param preserve_mode boolean|nil
---@param focus_after_attach boolean|nil
---@return qck.UiTabRecord|nil
local function create_and_attach_command(cmd, category_key, auto_close, preserve_mode, focus_after_attach)
  return ui.with_suppressed_focus_leave(function()
    local mode_intent = preserve_mode == true and capture_mode_intent() or nil
    local handle = terminal_service.create_handle(cmd, {
      interactive = true,
      auto_close = auto_close,
      win = vim.tbl_extend("force", layout.build_initial_terminal_config(), {
        position = "float",
      }),
    })
    if not handle then
      return nil
    end

    local tab_id, err = ui.attach_and_show(category_key, handle)
    if not tab_id then
      terminal_service.close_handle(handle)
      notify(err or "failed to attach terminal to ui", vim.log.levels.ERROR)
      return nil
    end

    restore_mode_intent(handle, mode_intent)
    if focus_after_attach == true then
      focus_terminal(handle)
    end
    return ui_state.get_tab(tab_id)
  end)
end

---@param preserve_mode boolean|nil
---@return qck.UiTabRecord|nil
function terminal.create_and_attach(preserve_mode)
  return create_and_attach_command(nil, UI_TERMINAL_CATEGORY_KEY, true, preserve_mode, false)
end

---@param cmd qck.Command
---@return qck.UiTabRecord|nil
function terminal.create_task_and_attach(cmd)
  local ok, err = ui.register_category(UI_TASK_CATEGORY)
  if not ok then
    notify(err or "failed to register task terminal category", vim.log.levels.ERROR)
    return nil
  end

  local key = task_command_key(cmd)
  local existing = find_task_tab_by_key(key)
  if existing then
    return show_existing_task_tab(existing)
  end

  local tab = create_and_attach_command(cmd, UI_TASK_CATEGORY.key, false, false, true)
  if tab and type(tab.terminal) == "table" then
    tab.terminal.qck_task_command_key = key
  end
  return tab
end

---@return nil
function terminal.open_active_or_create()
  if not ui.open_active() then
    terminal.create_and_attach()
  end
end

---@return nil
function terminal.toggle_active_or_create()
  if not ui.toggle_active() then
    terminal.create_and_attach()
  end
end

return terminal
