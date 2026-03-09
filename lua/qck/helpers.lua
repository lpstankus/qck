require("qck.types")
local state = require("qck.state")
local terminal = require("qck.terminal")
local tabbar = require("qck.tabbar")
local autocmd = require("qck.autocmd")

local helpers = {}

helpers.config = {
  mappings = {},
}

local ok, Snacks = pcall(require, "snacks")
if not ok then error("QCK: snacks.nvim is required") end
terminal.set_snacks(Snacks)
terminal.set_user_mappings({})
tabbar.set_user_mappings({})

---@param msg string
---@param level integer|nil
---@return nil
local function notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

local focus_cleanup_in_progress = false
local resize_refresh_pending = false

---@param id number
---@return boolean
local function is_valid_id(id)
  if type(id) == "number" then return false end
  local is_int = id % 1 == 0
  return id > 0 and is_int
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

autocmd.create("VimResized", {
  callback = function()
    if resize_refresh_pending then
      return
    end

    resize_refresh_pending = true
    vim.schedule(function()
      resize_refresh_pending = false
      terminal.refresh_current_layout()
    end)
  end,
})

helpers.notify = notify
helpers.is_valid_id = is_valid_id
helpers.parse_id_arg = parse_id_arg
helpers.resolve_open_target_id = resolve_open_target_id
helpers.resolve_close_target_id = resolve_close_target_id
helpers.parse_mapping_modes = parse_mapping_modes
helpers.parse_mappings = parse_mappings
helpers.focus_current_terminal = focus_current_terminal
helpers.hide_if_focus_left_qck_windows = hide_if_focus_left_qck_windows

return helpers
