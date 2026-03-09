local mappings = {}

---@param current_lhs string[]
---@param raw_mappings table|nil
---@return string[], table, string[]
function mappings.update_state(current_lhs, raw_mappings)
  local user_mappings = raw_mappings or {}
  local next_lhs = {}

  for lhs in pairs(user_mappings) do
    next_lhs[#next_lhs + 1] = lhs
  end
  table.sort(next_lhs)

  return current_lhs, user_mappings, next_lhs
end

---@param previous_lhs string[]
---@param current_lhs string[]
---@return table<string, boolean>
function mappings.collect_lhs_to_clear(previous_lhs, current_lhs)
  local lhs_to_clear = {}
  for _, lhs in ipairs(previous_lhs) do
    lhs_to_clear[lhs] = true
  end
  for _, lhs in ipairs(current_lhs) do
    lhs_to_clear[lhs] = true
  end
  return lhs_to_clear
end

return mappings
