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
  if not ok or type(data) ~= "table" or data.version ~= STORAGE_VERSION then
    ok, data = pcall(clean_data)
  end

  storage.ok = ok
  storage.version = STORAGE_VERSION
  storage.workspaces = ok and data.workspaces or {}
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
  if not storage.workspaces then
    storage.workspaces = {}
  end

  if not storage.workspaces[workspace] then
    storage.workspaces[workspace] = {
      builders = {},
    }
  end

  return storage.workspaces[workspace]
end

---@param workspace string
---@param builder_type string
---@return string|string[]|nil
function storage.get_builder_cmd(workspace, builder_type)
  if not storage.ok then
    return nil
  end

  local ws = storage.ensure_workspace(workspace)
  local builder = ws.builders[builder_type]
  if not builder then
    return nil
  end

  if type(builder.cmd) == "string" then
    return builder.cmd
  end

  if type(builder.cmd) == "table" then
    return clone_cmd(builder.cmd)
  end

  return nil
end

---@param workspace string
---@param builder_type string
---@param cmd string|string[]
---@return nil
function storage.set_builder_cmd(workspace, builder_type, cmd)
  if not storage.ok then
    return
  end

  local ws = storage.ensure_workspace(workspace)
  if not ws.builders[builder_type] then
    ws.builders[builder_type] = {}
  end

  ws.builders[builder_type].cmd = clone_cmd(cmd)
end

---@param workspace string
---@param builder_type string
---@return nil
function storage.reset_builder_cmd(workspace, builder_type)
  if not storage.ok then
    return
  end

  local ws = storage.ensure_workspace(workspace)
  if not ws.builders[builder_type] then
    return
  end

  ws.builders[builder_type].cmd = nil

  if not next(ws.builders[builder_type]) then
    ws.builders[builder_type] = nil
  end
end

return storage
