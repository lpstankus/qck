local layout = require("qck.ui.layout")
local ui = require("qck.ui")
local ui_state = require("qck.ui.state")
local terminal_service = require("qck.app.terminal.service")
local notify = require("qck.shared.notify").notify

local terminal = {}

local UI_TERMINAL_CATEGORY_KEY = "terminal"

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

---@param preserve_mode boolean|nil
---@return qck.UiTabRecord|nil
function terminal.create_and_attach(preserve_mode)
  return ui.with_suppressed_focus_leave(function()
    local mode_intent = preserve_mode == true and capture_mode_intent() or nil
    local handle = terminal_service.create_handle(nil, {
      interactive = true,
      auto_close = true,
      win = vim.tbl_extend("force", layout.build_initial_terminal_config(), {
        position = "float",
      }),
    })
    if not handle then
      return nil
    end

    local tab_id, err = ui.attach_and_show(UI_TERMINAL_CATEGORY_KEY, handle)
    if not tab_id then
      terminal_service.close_handle(handle)
      notify(err or "failed to attach terminal to ui", vim.log.levels.ERROR)
      return nil
    end

    restore_mode_intent(handle, mode_intent)
    return ui_state.get_tab(tab_id)
  end)
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
