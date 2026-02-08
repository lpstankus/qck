local helpers = require("qck.helpers")

local state = {}

---@class qck.TerminalMeta
---@field title? string

---@class qck.TerminalRecord
---@field win snacks.win
---@field meta qck.TerminalMeta

---@type table<number, qck.TerminalRecord>
local terminals = {}
local current_id = nil

function state.get_current_id()
  return current_id
end

function state.set_current_id(id)
  current_id = id
end

---@param id number
---@return qck.TerminalRecord?
function state.get_terminal(id)
  return terminals[id]
end

---@param id number
---@param rec qck.TerminalRecord
function state.set_terminal(id, rec)
  terminals[id] = rec
end

---@param id number
function state.remove_terminal(id)
  terminals[id] = nil
end

function state.prune_stale()
  for id, rec in pairs(terminals) do
    if not helpers.is_valid_record(rec) then
      terminals[id] = nil
    end
  end

  if current_id and not terminals[current_id] then
    current_id = nil
  end
end

---@return number[]
function state.live_ids()
  state.prune_stale()

  local ids = {}
  for id in pairs(terminals) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

function state.next_free_id()
  state.prune_stale()

  local id = 1
  while terminals[id] do
    id = id + 1
  end
  return id
end

---@param direction 1|-1
---@return number?
function state.get_cycle_id(direction)
  local ids = state.live_ids()
  if #ids == 0 then
    return nil
  end

  if not current_id or not terminals[current_id] then
    return direction == 1 and ids[1] or ids[#ids]
  end

  local idx = nil
  for i, id in ipairs(ids) do
    if id == current_id then
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

---@param removed_id number
function state.update_current_after_removal(removed_id)
  if current_id ~= removed_id then
    return
  end

  local ids = state.live_ids()
  current_id = ids[1]
end

return state
