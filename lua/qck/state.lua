local state = {}

local terminals = {}
local current_id = nil

---@param rec table|nil
---@return boolean
function state.is_valid_record(rec)
  return rec and rec.win and rec.win.buf_valid and rec.win:buf_valid() or false
end

---@param rec table|nil
---@return boolean
function state.is_window_open(rec)
  return rec and rec.win and rec.win.valid and rec.win:valid() or false
end

---@return integer|nil
function state.get_current_id()
  return current_id
end

---@param id integer|nil
---@return nil
function state.set_current_id(id)
  current_id = id
end

---@param id integer
---@return table|nil
function state.get_terminal(id)
  return terminals[id]
end

---@param id integer
---@param rec table
---@return nil
function state.set_terminal(id, rec)
  terminals[id] = rec
end

---@param id integer
---@return nil
function state.remove_terminal(id)
  terminals[id] = nil
end

---@return nil
function state.prune_stale()
  for id, rec in pairs(terminals) do
    if not state.is_valid_record(rec) then
      terminals[id] = nil
    end
  end

  if current_id and not terminals[current_id] then
    current_id = nil
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

---@param removed_id integer
---@return nil
function state.update_current_after_removal(removed_id)
  if current_id ~= removed_id then
    return
  end

  local ids = state.live_ids()
  current_id = ids[1]
end

return state
