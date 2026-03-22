local state = require("qck.terminal.state")
local notify = require("qck.shared.notify").notify

local targets = {}

---@param id number
---@return boolean
local function is_valid_id(id)
  if type(id) ~= "number" then return false end
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

targets.resolve_open_target_id = resolve_open_target_id
targets.resolve_close_target_id = resolve_close_target_id

return targets
