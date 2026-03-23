local runtime = {}

local content_winid = nil
local tabbar_bufnr = nil
local tabbar_winid = nil
local owner_to_handle = {}
local handle_to_owner = setmetatable({}, { __mode = "k" })
local owner_watchers = {}
local global_watchers = {}
local focus_target = nil

---@param value any
---@return integer|nil
local function normalize_winid(value)
  if type(value) ~= "number" or value % 1 ~= 0 then
    return nil
  end

  if not vim.api.nvim_win_is_valid(value) then
    return nil
  end

  return value
end

---@param value any
---@return integer|nil
local function normalize_bufnr(value)
  if type(value) ~= "number" or value % 1 ~= 0 then
    return nil
  end

  if not vim.api.nvim_buf_is_valid(value) then
    return nil
  end

  return value
end

---@param source table|nil
---@return table
local function copy_table(source)
  local out = {}
  if type(source) ~= "table" then
    return out
  end

  for key, value in pairs(source) do
    out[key] = value
  end

  return out
end

---@return nil
function runtime.reset()
  content_winid = nil
  tabbar_bufnr = nil
  tabbar_winid = nil
  owner_to_handle = {}
  handle_to_owner = setmetatable({}, { __mode = "k" })
  owner_watchers = {}
  global_watchers = {}
  focus_target = nil
end

---@param winid integer|nil
---@return nil
function runtime.set_content_winid(winid)
  content_winid = normalize_winid(winid)
end

---@return integer|nil
function runtime.get_content_winid()
  content_winid = normalize_winid(content_winid)
  return content_winid
end

---@return nil
function runtime.clear_content_winid()
  content_winid = nil
end

---@param bufnr integer|nil
---@return nil
function runtime.set_tabbar_bufnr(bufnr)
  tabbar_bufnr = normalize_bufnr(bufnr)
end

---@return integer|nil
function runtime.get_tabbar_bufnr()
  tabbar_bufnr = normalize_bufnr(tabbar_bufnr)
  return tabbar_bufnr
end

---@param winid integer|nil
---@return nil
function runtime.set_tabbar_winid(winid)
  tabbar_winid = normalize_winid(winid)
end

---@return integer|nil
function runtime.get_tabbar_winid()
  tabbar_winid = normalize_winid(tabbar_winid)
  return tabbar_winid
end

---@param bufnr integer|nil
---@param winid integer|nil
---@return nil
function runtime.set_tabbar_surface(bufnr, winid)
  runtime.set_tabbar_bufnr(bufnr)
  runtime.set_tabbar_winid(winid)
end

---@return nil
function runtime.clear_tabbar_winid()
  tabbar_winid = nil
end

---@return boolean
function runtime.is_visible()
  return runtime.get_content_winid() ~= nil
end

---@param target string|nil
---@return nil
function runtime.set_focus_target(target)
  if type(target) ~= "string" or target == "" then
    focus_target = nil
    return
  end

  focus_target = target
end

---@return string|nil
function runtime.get_focus_target()
  return focus_target
end

---@param owner_id any
---@param handle any
---@return boolean, string?
function runtime.register_handle(owner_id, handle)
  if owner_id == nil then
    return false, "owner id is required"
  end

  if handle == nil then
    return false, "handle is required"
  end

  local existing_owner = handle_to_owner[handle]
  if existing_owner ~= nil and existing_owner ~= owner_id then
    return false, "handle is already registered"
  end

  local existing_handle = owner_to_handle[owner_id]
  if existing_handle ~= nil and existing_handle ~= handle then
    return false, "owner id is already registered"
  end

  owner_to_handle[owner_id] = handle
  handle_to_owner[handle] = owner_id
  return true
end

---@param owner_id any
---@return any
function runtime.get_registered_handle(owner_id)
  return owner_to_handle[owner_id]
end

---@param handle any
---@return any
function runtime.get_handle_owner(handle)
  return handle_to_owner[handle]
end

---@param owner_id any
---@return nil
function runtime.unregister_handle(owner_id)
  local handle = owner_to_handle[owner_id]
  owner_to_handle[owner_id] = nil

  if handle ~= nil and handle_to_owner[handle] == owner_id then
    handle_to_owner[handle] = nil
  end
end

---@param owner_id any
---@param watchers table|nil
---@return nil
function runtime.set_owner_watchers(owner_id, watchers)
  if owner_id == nil then
    return
  end

  if type(watchers) ~= "table" then
    owner_watchers[owner_id] = nil
    return
  end

  owner_watchers[owner_id] = copy_table(watchers)
end

---@param owner_id any
---@return table
function runtime.get_owner_watchers(owner_id)
  return copy_table(owner_watchers[owner_id])
end

---@param owner_id any
---@return nil
function runtime.clear_owner_watchers(owner_id)
  owner_watchers[owner_id] = nil
end

---@param watchers table|nil
---@return nil
function runtime.set_global_watchers(watchers)
  global_watchers = copy_table(watchers)
end

---@return table
function runtime.get_global_watchers()
  return copy_table(global_watchers)
end

---@return nil
function runtime.clear_global_watchers()
  global_watchers = {}
end

return runtime
