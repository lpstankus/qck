-- Terminal id registry backed by UI-owned tab state.
--
-- UI state now owns terminal-tab ordering, active-tab selection, and reusable
-- `T#` display ids. This module keeps the remaining terminal id -> handle
-- mapping plus the current-id hint used by terminal creation and cycling.
local state = {}
local ui_state = require("qck.ui.state")

local terminals = {}
local current_id = nil

local UI_TERMINAL_CATEGORY_KEY = "terminal"
local UI_TERMINAL_CATEGORY_LABEL = "T"

---@return nil
local function ensure_ui_terminal_category()
  ui_state.register_category({ key = UI_TERMINAL_CATEGORY_KEY, label = UI_TERMINAL_CATEGORY_LABEL })
end

---@return integer|nil
local function resolve_ui_current_id()
  local tab_id = ui_state.resolve_active_tab()
  if not tab_id then
    return nil
  end

  local tab = ui_state.get_tab(tab_id)
  if not tab then
    return nil
  end

  return state.get_id_by_terminal(tab.terminal)
end

---@param rec qck.TerminalRecord|nil
---@return qck.UiTabId|nil
local function get_ui_tab_id(rec)
  local meta = rec and rec.meta or nil
  local tab_id = meta and meta.ui_tab_id or nil
  if type(tab_id) ~= "number" or tab_id % 1 ~= 0 then
    return nil
  end
  return tab_id
end

---@param rec qck.TerminalRecord|nil
---@param tab_id qck.UiTabId|nil
---@return nil
local function set_ui_tab_id(rec, tab_id)
  if type(rec) ~= "table" then
    return
  end

  if type(rec.meta) ~= "table" then
    rec.meta = {}
  end

  if type(tab_id) == "number" and tab_id % 1 == 0 then
    rec.meta.ui_tab_id = tab_id
  else
    rec.meta.ui_tab_id = nil
  end
end

---@param tab_id qck.UiTabId|nil
---@return integer|nil
local function get_id_by_tab_id(tab_id)
  local tab = type(tab_id) == "number" and ui_state.get_tab(tab_id) or nil
  if not tab then
    return nil
  end

  return state.get_id_by_terminal(tab.terminal)
end

---@param rec qck.TerminalRecord|nil
---@return boolean
function state.is_valid_record(rec)
  if type(rec) ~= "table" or type(rec.win) ~= "table" then
    return false
  end

  if type(rec.win.buf_valid) ~= "function" then
    return false
  end

  local ok, valid = pcall(function() return rec.win:buf_valid() end)
  return ok and valid == true
end

---@param rec qck.TerminalRecord|nil
---@return boolean
function state.is_window_open(rec)
  if type(rec) ~= "table" or type(rec.win) ~= "table" then
    return false
  end

  if type(rec.win.valid) ~= "function" then
    return false
  end

  local ok, valid = pcall(function() return rec.win:valid() end)
  return ok and valid == true
end

---@return integer|nil
function state.get_current_id()
  state.prune_stale()

  local resolved_id = resolve_ui_current_id()
  if resolved_id ~= nil and terminals[resolved_id] then
    current_id = resolved_id
    return current_id
  end

  local ids = state.ordered_ids()
  current_id = ids[1]
  return current_id
end

---@param id integer|nil
---@return nil
function state.set_current_id(id)
  current_id = type(id) == "number" and id or nil
end

---@param id integer
---@return qck.TerminalRecord|nil
function state.get_terminal(id)
  return terminals[id]
end

---@param id integer
---@param rec qck.TerminalRecord
---@return nil
function state.set_terminal(id, rec)
  terminals[id] = rec
end

---@param id integer
---@return nil
function state.remove_terminal(id)
  terminals[id] = nil
end

---@param id integer
---@return integer|nil
function state.get_label_id(id)
  local tab_id = state.get_tab_id(id)
  local tab = tab_id and ui_state.get_tab(tab_id) or nil
  return tab and tab.category_display_id or nil
end

---@return nil
function state.prune_stale()
  local removed = false

  for id, rec in pairs(terminals) do
    if not state.is_valid_record(rec) then
      local tab_id = get_ui_tab_id(rec)
      if tab_id then
        local ok_ui, ui = pcall(require, "qck.ui")
        if ok_ui and type(ui.clear_watchers_for_tab) == "function" then
          ui.clear_watchers_for_tab(tab_id)
        end
        ui_state.delete_tab(tab_id)
        set_ui_tab_id(rec, nil)
      end
      terminals[id] = nil
      removed = true
    end
  end

  if removed then
    state.sync_current_from_ui()
  end
end

---@return integer[]
function state.live_ids()
  state.prune_stale()

  local ids = {}
  for id in pairs(terminals) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

---@return integer[]
function state.ordered_ids()
  state.prune_stale()

  local ordered = {}
  local seen = {}

  ensure_ui_terminal_category()

  for _, tab_id in ipairs(ui_state.category_tab_ids(UI_TERMINAL_CATEGORY_KEY)) do
    local id = get_id_by_tab_id(tab_id)
    if id and terminals[id] and not seen[id] then
      ordered[#ordered + 1] = id
      seen[id] = true
    end
  end

  local remaining = {}
  for id in pairs(terminals) do
    if not seen[id] then
      remaining[#remaining + 1] = id
    end
  end
  table.sort(remaining)

  for _, id in ipairs(remaining) do
    ordered[#ordered + 1] = id
  end

  return ordered
end

---@param id integer
---@param direction integer
---@return boolean
function state.move_id(id, direction)
  if type(id) ~= "number" or id % 1 ~= 0 then
    return false
  end

  if direction ~= -1 and direction ~= 1 then
    return false
  end

  state.prune_stale()
  if not terminals[id] then
    return false
  end

  local tab_id = state.get_tab_id(id)
  if not tab_id then
    return false
  end

  return ui_state.move_tab(tab_id, direction)
end

---@param id integer
---@return qck.UiTabId|nil
function state.get_tab_id(id)
  return get_ui_tab_id(terminals[id])
end

---@param id integer
---@param tab_id qck.UiTabId|nil
---@return nil
function state.set_tab_id(id, tab_id)
  set_ui_tab_id(terminals[id], tab_id)
end

---@return nil
function state.sync_current_from_ui()
  current_id = resolve_ui_current_id()
end

---@param handle any
---@return integer|nil
function state.get_id_by_terminal(handle)
  if handle == nil then
    return nil
  end

  for id, rec in pairs(terminals) do
    if rec and rec.win == handle then
      return id
    end
  end

  return nil
end

---@return integer
function state.next_free_id()
  state.prune_stale()

  local id = 1
  while terminals[id] do
    id = id + 1
  end
  return id
end

---@param direction integer
---@return integer|nil
function state.get_cycle_id(direction)
  local ids = state.ordered_ids()
  if #ids == 0 then
    return nil
  end

  local active_id = resolve_ui_current_id()
  current_id = active_id

  if not active_id or not terminals[active_id] then
    return direction == 1 and ids[1] or ids[#ids]
  end

  local idx = nil
  for i, id in ipairs(ids) do
    if id == active_id then
      idx = i
      break
    end
  end

  if not idx then
    return direction == 1 and ids[1] or ids[#ids]
  end

  local next_idx = idx + direction
  if next_idx < 1 then
    next_idx = #ids
  elseif next_idx > #ids then
    next_idx = 1
  end

  return ids[next_idx]
end

---@param removed_id integer
---@return nil
function state.update_current_after_removal(removed_id)
  current_id = resolve_ui_current_id()
end

return state
