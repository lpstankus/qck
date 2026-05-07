-- Pure UI registry state for the internal handoff migration.
--
-- This module owns category metadata, per-category tab ordering, reusable
-- category display ids, global traversal order, and active-tab fallback rules.
-- Runtime window orchestration still lives elsewhere until later chunks move it.
local state = {}

local categories = {}
local category_order = {}
local tabs = {}
local terminal_to_tab = setmetatable({}, { __mode = "k" })
local active_tab_id = nil
local category_active_tab_ids = {}
local next_tab_id = 1

---@param values integer[]
---@return integer[]
local function copy_ids(values)
  local out = {}
  for i, value in ipairs(values) do
    out[i] = value
  end
  return out
end

---@param category qck.UiCategoryRecord
---@return qck.UiCategoryRecord
local function copy_category(category)
  return {
    key = category.key,
    label = category.label,
    order = category.order,
    tab_ids = copy_ids(category.tab_ids),
  }
end

---@param tab qck.UiTabRecord
---@return qck.UiTabRecord
local function copy_tab(tab)
  return {
    id = tab.id,
    category_key = tab.category_key,
    category_label = tab.category_label,
    category_display_id = tab.category_display_id,
    terminal = tab.terminal,
  }
end

---@param tab_id integer|nil
---@return boolean
local function is_live_tab_id(tab_id)
  return type(tab_id) == "number" and tab_id % 1 == 0 and tabs[tab_id] ~= nil
end

---@param key any
---@return qck.UiCategoryRecord|nil
local function get_category_record(key)
  if type(key) ~= "string" or key == "" then
    return nil
  end
  return categories[key]
end

---@param category qck.UiCategoryRecord
---@return integer
local function next_free_display_id(category)
  local used = {}

  for _, tab_id in ipairs(category.tab_ids) do
    local tab = tabs[tab_id]
    local display_id = tab and tab.category_display_id or nil
    if type(display_id) == "number" and display_id > 0 and display_id % 1 == 0 then
      used[display_id] = true
    end
  end

  local next_id = 1
  while used[next_id] do
    next_id = next_id + 1
  end

  return next_id
end

---@param display_id any
---@return boolean
local function is_valid_display_id(display_id)
  return type(display_id) == "number" and display_id > 0 and display_id % 1 == 0
end

---@param category qck.UiCategoryRecord
---@return nil
local function sort_category_tabs_by_display_id(category)
  table.sort(category.tab_ids, function(left_id, right_id)
    local left = tabs[left_id]
    local right = tabs[right_id]
    local left_display_id = left and left.category_display_id or math.huge
    local right_display_id = right and right.category_display_id or math.huge

    if left_display_id == right_display_id then
      return left_id < right_id
    end

    return left_display_id < right_display_id
  end)
end

---@return integer[]
local function build_traversal_ids()
  local ordered = {}

  for _, category_key in ipairs(category_order) do
    local category = categories[category_key]
    if category then
      for _, tab_id in ipairs(category.tab_ids) do
        if tabs[tab_id] then
          ordered[#ordered + 1] = tab_id
        end
      end
    end
  end

  return ordered
end

---@param tab_id integer
---@return integer|nil, integer[]
local function traversal_index(tab_id)
  local ordered = build_traversal_ids()

  for index, candidate in ipairs(ordered) do
    if candidate == tab_id then
      return index, ordered
    end
  end

  return nil, ordered
end

---@param category_key string
---@param label string
---@param existing_category qck.UiCategoryRecord|nil
---@return boolean, string?
local function validate_category_spec(category_key, label, existing_category)
  if category_key == "" then
    return false, "category key must be a non-empty string"
  end

  if label == "" then
    return false, "category label must be a non-empty string"
  end

  for existing_key, category in pairs(categories) do
    if existing_key ~= category_key and category.label == label then
      return false, "category label already registered"
    end
  end

  if existing_category and #existing_category.tab_ids > 0 and existing_category.label ~= label then
    return false, "category metadata does not match existing registration"
  end

  return true
end

---@return nil
function state.reset()
  categories = {}
  category_order = {}
  tabs = {}
  terminal_to_tab = setmetatable({}, { __mode = "k" })
  active_tab_id = nil
  category_active_tab_ids = {}
  next_tab_id = 1
end

---@param spec qck.UiCategorySpec
---@return boolean, string?
function state.register_category(spec)
  if type(spec) ~= "table" then
    return false, "category spec must be a table"
  end

  local key = type(spec.key) == "string" and spec.key or ""
  local label = type(spec.label) == "string" and spec.label or ""
  local existing = categories[key]
  local ok, err = validate_category_spec(key, label, existing)
  if not ok then
    return false, err
  end

  if existing then
    if existing.label ~= label then
      existing.label = label
    end
    return true
  end

  categories[key] = {
    key = key,
    label = label,
    order = #category_order + 1,
    tab_ids = {},
  }
  category_order[#category_order + 1] = key
  return true
end

---@param key qck.UiCategoryKey
---@return qck.UiCategoryRecord|nil
function state.get_category(key)
  local category = get_category_record(key)
  if not category then
    return nil
  end
  return copy_category(category)
end

---@return qck.UiCategoryKey[]
function state.category_keys()
  local keys = {}
  for i, key in ipairs(category_order) do
    keys[i] = key
  end
  return keys
end

---@param category_key qck.UiCategoryKey
---@return qck.UiTabId[]
function state.category_tab_ids(category_key)
  local category = get_category_record(category_key)
  if not category then
    return {}
  end
  return copy_ids(category.tab_ids)
end

---@return qck.UiTabId[]
function state.traversal_ids()
  return build_traversal_ids()
end

---@param tab_id qck.UiTabId
---@return qck.UiTabRecord|nil
function state.get_tab(tab_id)
  local tab = tabs[tab_id]
  if not tab then
    return nil
  end
  return copy_tab(tab)
end

---@param terminal any
---@return qck.UiTabRecord|nil
function state.get_tab_by_terminal(terminal)
  local tab_id = terminal_to_tab[terminal]
  if not tab_id then
    return nil
  end
  return state.get_tab(tab_id)
end

---@return qck.UiTabId|nil
function state.get_active_tab_id()
  return active_tab_id
end

---@param tab_id qck.UiTabId|nil
---@return nil
function state.set_active_tab_id(tab_id)
  active_tab_id = tab_id
end

---@return qck.UiTabId|nil
function state.resolve_active_tab()
  if is_live_tab_id(active_tab_id) then
    return active_tab_id
  end

  local ordered = build_traversal_ids()
  active_tab_id = ordered[1]
  return active_tab_id
end

---@param tab_id qck.UiTabId
---@return boolean, string?
function state.set_active_tab(tab_id)
  if not is_live_tab_id(tab_id) then
    return false, "tab is not registered"
  end

  local tab = tabs[tab_id]
  active_tab_id = tab_id
  category_active_tab_ids[tab.category_key] = tab_id
  return true
end

---@param category_key qck.UiCategoryKey
---@return qck.UiTabId|nil
function state.get_active_category_tab_id(category_key)
  local tab_id = category_active_tab_ids[category_key]
  if is_live_tab_id(tab_id) then
    return tab_id
  end

  category_active_tab_ids[category_key] = nil
  return nil
end

---@param category_key qck.UiCategoryKey
---@param terminal any
---@param opts? qck.UiRegisterTabOpts
---@return qck.UiTabId|nil, string?
function state.register_tab(category_key, terminal, opts)
  local category = get_category_record(category_key)
  if not category then
    return nil, "category is not registered"
  end

  if terminal == nil then
    return nil, "tab terminal is required"
  end

  if terminal_to_tab[terminal] then
    return nil, "terminal is already registered"
  end

  local display_id = opts and opts.display_id or nil
  if display_id ~= nil and not is_valid_display_id(display_id) then
    return nil, "display id must be a positive integer"
  end

  local tab_id = next_tab_id
  next_tab_id = next_tab_id + 1

  local tab = {
    id = tab_id,
    category_key = category.key,
    category_label = category.label,
    category_display_id = display_id or next_free_display_id(category),
    terminal = terminal,
  }

  tabs[tab_id] = tab
  category.tab_ids[#category.tab_ids + 1] = tab_id
  if display_id ~= nil then
    category.sort_by_display_id = true
    sort_category_tabs_by_display_id(category)
  end
  terminal_to_tab[terminal] = tab_id
  state.resolve_active_tab()
  return tab_id
end

---@param tab_id qck.UiTabId
---@param display_id qck.UiDisplayId
---@return boolean, string?
function state.set_tab_display_id(tab_id, display_id)
  if not is_valid_display_id(display_id) then
    return false, "display id must be a positive integer"
  end

  local tab = tabs[tab_id]
  if not tab then
    return false, "tab is not registered"
  end

  tab.category_display_id = display_id
  local category = categories[tab.category_key]
  if category then
    category.sort_by_display_id = true
    sort_category_tabs_by_display_id(category)
  end
  return true
end

---@param tab_id qck.UiTabId
---@return boolean, string?
function state.delete_tab(tab_id)
  local tab = tabs[tab_id]
  if not tab then
    return false, "tab is not registered"
  end

  local category = categories[tab.category_key]
  if not category then
    return false, "tab category is not registered"
  end

  local index, ordered = traversal_index(tab_id)
  local next_active = nil
  if active_tab_id == tab_id and index then
    next_active = ordered[index + 1] or ordered[index - 1]
  end

  local category_index = nil
  for i, candidate in ipairs(category.tab_ids) do
    if candidate == tab_id then
      category_index = i
      break
    end
  end

  local next_category_active = nil
  if category_index then
    for candidate_index = category_index + 1, #category.tab_ids do
      next_category_active = category.tab_ids[candidate_index]
      break
    end
    if not next_category_active then
      for candidate_index = category_index - 1, 1, -1 do
        next_category_active = category.tab_ids[candidate_index]
        break
      end
    end
  end

  for i, candidate in ipairs(category.tab_ids) do
    if candidate == tab_id then
      table.remove(category.tab_ids, i)
      break
    end
  end

  tabs[tab_id] = nil
  terminal_to_tab[tab.terminal] = nil
  if category_active_tab_ids[tab.category_key] == tab_id then
    category_active_tab_ids[tab.category_key] = next_category_active
  end

  if active_tab_id == tab_id then
    active_tab_id = next_active
    local next_tab = tabs[next_active]
    if next_tab then
      category_active_tab_ids[next_tab.category_key] = next_active
    end
  else
    state.resolve_active_tab()
  end

  return true
end

---@param tab_id qck.UiTabId
---@param direction integer
---@return boolean, string?
function state.move_tab(tab_id, direction)
  if direction ~= -1 and direction ~= 1 then
    return false, "direction must be -1 or 1"
  end

  local tab = tabs[tab_id]
  if not tab then
    return false, "tab is not registered"
  end

  local category = categories[tab.category_key]
  if not category then
    return false, "tab category is not registered"
  end

  if category.sort_by_display_id then
    return false, "category is sorted by display id"
  end

  local index = nil
  for i, candidate in ipairs(category.tab_ids) do
    if candidate == tab_id then
      index = i
      break
    end
  end

  if not index then
    return false, "tab is not ordered"
  end

  local swap_index = index + direction
  if swap_index < 1 or swap_index > #category.tab_ids then
    return false
  end

  category.tab_ids[index], category.tab_ids[swap_index] = category.tab_ids[swap_index], category.tab_ids[index]
  return true
end

---@param direction integer
---@return qck.UiTabId|nil
function state.get_cycle_tab_id(direction)
  if direction ~= -1 and direction ~= 1 then
    return nil
  end

  local ordered = build_traversal_ids()
  if #ordered == 0 then
    return nil
  end

  local active = state.resolve_active_tab()
  if not active then
    return direction == 1 and ordered[1] or ordered[#ordered]
  end

  for index, tab_id in ipairs(ordered) do
    if tab_id == active then
      local next_index = index + direction
      if next_index < 1 then
        next_index = #ordered
      elseif next_index > #ordered then
        next_index = 1
      end
      return ordered[next_index]
    end
  end

  return direction == 1 and ordered[1] or ordered[#ordered]
end

state.reset()

return state
