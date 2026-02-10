local storage = {}

local STORAGE_VERSION = "0.1.0"
local storage_path = vim.fn.stdpath("data") .. "/qck.json"

storage.ok = false
storage.version = STORAGE_VERSION
storage.workspaces = {}

---@param cmd string|string[]
---@return string|string[]
local function clone_cmd(cmd)
  if type(cmd) == "string" then
    return cmd
  end

  local copy = {}
  for i, part in ipairs(cmd) do
    copy[i] = part
  end
  return copy
end

---@param value any
---@return string|string[]|nil
local function normalize_cmd(value)
  if type(value) == "string" then
    if vim.trim(value) == "" then
      return nil
    end
    return value
  end

  if type(value) ~= "table" or #value == 0 then
    return nil
  end

  local parsed = {}
  for i, part in ipairs(value) do
    if type(part) ~= "string" or vim.trim(part) == "" then
      return nil
    end
    parsed[i] = part
  end

  return parsed
end

---@param data any
---@return table|nil
local function sanitize_data(data)
  if type(data) ~= "table" then
    return nil
  end

  local sanitized = {
    version = STORAGE_VERSION,
    workspaces = {},
  }

  if type(data.workspaces) ~= "table" then
    return sanitized
  end

  for workspace, ws in pairs(data.workspaces) do
    if type(workspace) == "string" and workspace ~= "" and type(ws) == "table" then
      local builders = {}
      local ws_builders = ws.builders

      if type(ws_builders) == "table" then
        for builder_type, builder in pairs(ws_builders) do
          if type(builder_type) == "string" then
            local normalized_builder_type = vim.trim(builder_type)
            if normalized_builder_type ~= "" and not builders[normalized_builder_type] then
              local cmd = normalize_cmd(type(builder) == "table" and builder.cmd or nil)
              if cmd then
                builders[normalized_builder_type] = {
                  cmd = clone_cmd(cmd),
                }
              end
            end
          end
        end
      end

      if next(builders) then
        sanitized.workspaces[workspace] = {
          builders = builders,
        }
      end
    end
  end

  return sanitized
end

---@param data table
---@return nil
local function write_data(data)
  local encoded = vim.json.encode(data)
  vim.fn.writefile({ encoded }, storage_path)
end

---@return table
local function clean_data()
  local blank = {
    version = STORAGE_VERSION,
    workspaces = {},
  }
  write_data(blank)
  return blank
end

---@return table
local function read_data()
  if vim.fn.filereadable(storage_path) == 0 then
    return clean_data()
  end

  local lines = vim.fn.readfile(storage_path)
  if not lines or #lines == 0 then
    return clean_data()
  end

  local decoded = vim.json.decode(table.concat(lines, "\n"))
  if type(decoded) ~= "table" then
    return clean_data()
  end

  return decoded
end

---@return boolean
function storage.load()
  local ok, data = pcall(read_data)
  local sanitized = nil

  if ok and type(data) == "table" and data.version == STORAGE_VERSION then
    sanitized = sanitize_data(data)
  end

  if not sanitized then
    ok, data = pcall(clean_data)
    if ok then
      sanitized = sanitize_data(data)
    end
  end

  storage.ok = ok and sanitized ~= nil
  storage.version = STORAGE_VERSION
  storage.workspaces = storage.ok and sanitized.workspaces or {}
  return storage.ok
end

---@return boolean
function storage.save()
  if not storage.ok then
    return false
  end

  local ok = pcall(write_data, {
    version = STORAGE_VERSION,
    workspaces = storage.workspaces,
  })
  return ok
end

---@param workspace string
---@return table
function storage.ensure_workspace(workspace)
  if type(storage.workspaces) ~= "table" then
    storage.workspaces = {}
  end

  if not storage.workspaces[workspace] then
    storage.workspaces[workspace] = {
      builders = {},
    }
  end

  if type(storage.workspaces[workspace].builders) ~= "table" then
    storage.workspaces[workspace].builders = {}
  end

  return storage.workspaces[workspace]
end

---@param workspace string
---@param builder_type string
---@return string|string[]|nil
function storage.get_builder_cmd(workspace, builder_type)
  if not storage.ok or type(storage.workspaces) ~= "table" then
    return nil
  end

  if type(workspace) ~= "string" or workspace == "" then
    return nil
  end

  if type(builder_type) ~= "string" then
    return nil
  end

  local normalized_builder_type = vim.trim(builder_type)
  if normalized_builder_type == "" then
    return nil
  end

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.builders) ~= "table" then
    return nil
  end

  local builder = ws.builders[normalized_builder_type]
  if type(builder) ~= "table" then
    return nil
  end

  local cmd = normalize_cmd(builder.cmd)
  if not cmd then
    return nil
  end

  return clone_cmd(cmd)
end

---@param workspace string
---@param builder_type string
---@param cmd string|string[]
---@return nil
function storage.set_builder_cmd(workspace, builder_type, cmd)
  if not storage.ok then
    return
  end

  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  if type(builder_type) ~= "string" then
    return
  end

  local normalized_builder_type = vim.trim(builder_type)
  if normalized_builder_type == "" then
    return
  end

  local ws = storage.ensure_workspace(workspace)
  if not ws.builders[normalized_builder_type] then
    ws.builders[normalized_builder_type] = {}
  end

  ws.builders[normalized_builder_type].cmd = clone_cmd(cmd)
end

---@param workspace string
---@param builder_type string
---@return nil
function storage.reset_builder_cmd(workspace, builder_type)
  if not storage.ok then
    return
  end

  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  if type(builder_type) ~= "string" then
    return
  end

  local normalized_builder_type = vim.trim(builder_type)
  if normalized_builder_type == "" then
    return
  end

  local ws = storage.ensure_workspace(workspace)
  if not ws.builders[normalized_builder_type] then
    return
  end

  ws.builders[normalized_builder_type].cmd = nil

  if not next(ws.builders[normalized_builder_type]) then
    ws.builders[normalized_builder_type] = nil
  end
end

return storage
