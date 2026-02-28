local state = {}

local terminals = {}
local current_id = nil
local long_running_order = {}
local default_order = {}

---@param ids integer[]
---@return integer[]
local function copy_ids(ids)
  local out = {}
  for i, id in ipairs(ids) do
    out[i] = id
  end
  return out
end

---@param existing integer[]
---@param live_ids integer[]
---@return integer[]
local function sync_kind_order(existing, live_ids)
  local live_lookup = {}
  for _, id in ipairs(live_ids) do
    live_lookup[id] = true
  end

  local ordered = {}
  local seen = {}
  for _, id in ipairs(existing) do
    if live_lookup[id] and not seen[id] then
      ordered[#ordered + 1] = id
      seen[id] = true
    end
  end

  for _, id in ipairs(live_ids) do
    if not seen[id] then
      ordered[#ordered + 1] = id
    end
  end

  return ordered
end

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
  state.sync_orders()
end

---@param id integer
---@return nil
function state.remove_terminal(id)
  terminals[id] = nil
  state.sync_orders()
end

---@return nil
function state.sync_orders()
  local long_running_ids = {}
  local default_ids = {}

  for id in pairs(terminals) do
    if state.is_long_running(id) then
      long_running_ids[#long_running_ids + 1] = id
    else
      default_ids[#default_ids + 1] = id
    end
  end

  table.sort(long_running_ids)
  table.sort(default_ids)
  long_running_order = sync_kind_order(long_running_order, long_running_ids)
  default_order = sync_kind_order(default_order, default_ids)
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

  state.sync_orders()
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

---@param id integer
---@return boolean
function state.is_long_running(id)
  local rec = terminals[id]
  return rec and rec.meta and rec.meta.kind == "long_running" or false
end

---@param id integer
---@return string|nil
function state.get_terminal_kind(id)
  local rec = terminals[id]
  return rec and rec.meta and rec.meta.kind or nil
end

---@param id integer
---@return string|nil
function state.get_builder_type(id)
  local rec = terminals[id]
  return rec and rec.meta and rec.meta.builder_type or nil
end

---@param builder_type string
---@return integer|nil
function state.find_terminal_id_by_builder_type(builder_type)
  if type(builder_type) ~= "string" or builder_type == "" then
    return nil
  end

  local ids = state.live_ids()
  for _, id in ipairs(ids) do
    if state.get_builder_type(id) == builder_type then
      return id
    end
  end

  return nil
end

---@return integer[], integer[], integer[]
function state.partitioned_ids()
  state.prune_stale()

  local all_ids = {}
  for id in pairs(terminals) do
    all_ids[#all_ids + 1] = id
  end

  table.sort(all_ids)

  return all_ids, copy_ids(long_running_order), copy_ids(default_order)
end

---@return integer[]
function state.ordered_ids()
  local _, long_running_ids, default_ids = state.partitioned_ids()
  local ids = {}

  for _, id in ipairs(long_running_ids) do
    ids[#ids + 1] = id
  end

  for _, id in ipairs(default_ids) do
    ids[#ids + 1] = id
  end

  return ids
end

---@param id integer
---@param direction integer
---@return boolean
function state.move_id_within_kind(id, direction)
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

  local order = state.is_long_running(id) and long_running_order or default_order
  local idx = nil
  for i, candidate in ipairs(order) do
    if candidate == id then
      idx = i
      break
    end
  end

  if not idx then
    return false
  end

  local swap_idx = idx + direction
  if swap_idx < 1 or swap_idx > #order then
    return false
  end

  order[idx], order[swap_idx] = order[swap_idx], order[idx]
  return true
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

  local ids = state.ordered_ids()
  current_id = ids[1]
end

return state
