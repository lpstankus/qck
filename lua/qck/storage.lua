local storage = {}
local cmd_util = require("qck.cmd")

local STORAGE_VERSION = "0.1.0"
local storage_path = vim.fn.stdpath("data") .. "/qck.json"

storage.ok = false
storage.version = STORAGE_VERSION
storage.workspaces = {}
storage.last_error = nil

---@param data any
---@return qck.StorageState|nil
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
              local cmd = cmd_util.normalize(type(builder) == "table" and builder.cmd or nil)
              if cmd then
                builders[normalized_builder_type] = {
                  cmd = cmd_util.clone(cmd),
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

---@param data qck.StorageState
---@return nil
local function write_data(data)
  local encoded = vim.json.encode(data)
  vim.fn.writefile({ encoded }, storage_path)
end

---@return qck.StorageState
local function clean_data()
  local blank = {
    version = STORAGE_VERSION,
    workspaces = {},
  }
  write_data(blank)
  return blank
end

---@return qck.StorageState
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

---@return boolean, string|nil
function storage.load()
  local sanitized = nil
  local err = nil

  local ok_read, data_or_err = pcall(read_data)
  if ok_read and type(data_or_err) == "table" and data_or_err.version == STORAGE_VERSION then
    sanitized = sanitize_data(data_or_err)
    if not sanitized then
      err = "failed to sanitize storage data"
    end
  elseif not ok_read then
    err = ("failed to read storage file: %s"):format(tostring(data_or_err))
  else
    err = "storage file has unsupported format/version"
  end

  if not sanitized then
    local ok_reset, reset_or_err = pcall(clean_data)
    if ok_reset and type(reset_or_err) == "table" then
      sanitized = sanitize_data(reset_or_err)
      if not sanitized then
        err = "failed to sanitize reset storage data"
      end
    else
      err = ("failed to reset storage file: %s"):format(tostring(reset_or_err))
    end
  end

  storage.ok = sanitized ~= nil
  storage.version = STORAGE_VERSION
  storage.workspaces = storage.ok and sanitized.workspaces or {}
  storage.last_error = storage.ok and nil or (err or "failed to load storage")
  return storage.ok, storage.last_error
end

---@return boolean, string|nil
function storage.save()
  if not storage.ok then
    storage.last_error = "storage is not loaded"
    return false, storage.last_error
  end

  local ok, write_err = pcall(write_data, {
    version = STORAGE_VERSION,
    workspaces = storage.workspaces,
  })
  if not ok then
    storage.last_error = ("failed to write `%s`: %s"):format(storage_path, tostring(write_err))
    return false, storage.last_error
  end

  storage.last_error = nil
  return true, nil
end

---@param workspace string
---@return qck.StorageWorkspaceState
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
---@return qck.Command|nil
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

  local cmd = cmd_util.normalize(builder.cmd)
  if not cmd then
    return nil
  end

  return cmd_util.clone(cmd)
end

---@param workspace string
---@param builder_type string
---@param cmd qck.Command
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

  ws.builders[normalized_builder_type].cmd = cmd_util.clone(cmd)
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
