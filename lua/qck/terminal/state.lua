-- Current pre-migration terminal registry and traversal state.
--
-- The target UI handoff contract is documented in
-- `plans/2-ui-handoff-contract.md`. Today this module still owns the current
-- active terminal id, global traversal order, and reusable `T#` label ids.
-- Those concerns are documented now so later `lua/qck/ui/` work can migrate
-- them without changing the written rules for stale-active fallback,
-- category-local motion, global traversal, or display-label reuse.
local state = {}

local terminals = {}
local current_id = nil
local terminal_order = {}

---@param value any
---@return boolean
local function is_valid_label_id(value)
  return type(value) == "number" and value > 0 and value % 1 == 0
end

---@return integer
local function next_free_label_id()
  local used = {}

  for _, rec in pairs(terminals) do
    local label_id = rec and rec.meta and rec.meta.label_id
    if is_valid_label_id(label_id) then
      used[label_id] = true
    end
  end

  local next_id = 1
  while used[next_id] do
    next_id = next_id + 1
  end

  return next_id
end

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
local function sync_order(existing, live_ids)
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
  return current_id
end

---@param id integer|nil
---@return nil
function state.set_current_id(id)
  current_id = id
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
  state.assign_label_id(id)
  state.sync_order()
end

---@param id integer
---@return nil
function state.remove_terminal(id)
  terminals[id] = nil
  state.sync_order()
end

---@param id integer
---@return integer|nil
function state.assign_label_id(id)
  local rec = terminals[id]
  if type(rec) ~= "table" then
    return nil
  end

  if type(rec.meta) ~= "table" then
    rec.meta = {}
  end

  local label_id = rec.meta.label_id
  if is_valid_label_id(label_id) then
    return label_id
  end

  rec.meta.label_id = next_free_label_id()
  return rec.meta.label_id
end

---@param id integer
---@return integer|nil
function state.get_label_id(id)
  return state.assign_label_id(id)
end

---@return nil
function state.sync_order()
  local ids = {}

  for id in pairs(terminals) do
    ids[#ids + 1] = id
  end

  table.sort(ids)
  terminal_order = sync_order(terminal_order, ids)
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

  state.sync_order()
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
  return copy_ids(terminal_order)
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

  local idx = nil
  for i, candidate in ipairs(terminal_order) do
    if candidate == id then
      idx = i
      break
    end
  end

  if not idx then
    return false
  end

  local swap_idx = idx + direction
  if swap_idx < 1 or swap_idx > #terminal_order then
    return false
  end

  terminal_order[idx], terminal_order[swap_idx] = terminal_order[swap_idx], terminal_order[idx]
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
