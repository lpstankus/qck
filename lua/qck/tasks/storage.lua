local storage = {}
local cmd_util = require("qck.shared.cmd")

local STORAGE_VERSION = "0.1.0"
local storage_path = vim.fn.stdpath("data") .. "/qck.json"

storage.ok = false
storage.version = STORAGE_VERSION
storage.workspaces = vim.empty_dict()
storage.last_error = nil

---@return table
local function empty_map()
  return vim.empty_dict()
end

---@param tbl table
---@param allowed table<string, boolean>
---@return boolean
local function has_only_allowed_keys(tbl, allowed)
  for key in pairs(tbl) do
    if type(key) ~= "string" or not allowed[key] then
      return false
    end
  end
  return true
end

---@return qck.StorageState
local function blank_state()
  return {
    version = STORAGE_VERSION,
    workspaces = empty_map(),
  }
end

---@param data any
---@return qck.StorageState|nil, string|nil
local function sanitize_data(data)
  if type(data) ~= "table" then
    return nil, "storage root must be a table"
  end

  local allowed_root_keys = {
    version = true,
    workspaces = true,
  }

  if not has_only_allowed_keys(data, allowed_root_keys) then
    return nil, "storage root contains unsupported fields"
  end

  if data.version ~= STORAGE_VERSION then
    return nil, "storage file has unsupported version"
  end

  if type(data.workspaces) ~= "table" then
    return nil, "storage workspaces must be a table"
  end

  local sanitized = blank_state()

  for workspace, ws in pairs(data.workspaces) do
    if type(workspace) ~= "string" or workspace == "" then
      return nil, "workspace keys must be non-empty strings"
    end

    if type(ws) ~= "table" then
      return nil, "workspace state must be a table"
    end

    local allowed_workspace_keys = {
      tasks = true,
    }

    if not has_only_allowed_keys(ws, allowed_workspace_keys) then
      return nil, ("workspace `%s` contains unsupported fields"):format(workspace)
    end

    if type(ws.tasks) ~= "table" then
      return nil, ("workspace `%s`.tasks must be a table"):format(workspace)
    end

    local tasks = {}

    for task_type, task_state in pairs(ws.tasks) do
      if type(task_type) ~= "string" then
        return nil, ("workspace `%s` has non-string task type key"):format(workspace)
      end

      local normalized_task_type = vim.trim(task_type)
      if normalized_task_type == "" then
        return nil, ("workspace `%s` has empty task type key"):format(workspace)
      end

      if tasks[normalized_task_type] then
        return nil, ("workspace `%s` has duplicate task `%s` after normalization"):format(workspace, normalized_task_type)
      end

      if type(task_state) ~= "table" then
        return nil, ("workspace `%s` task `%s` must be a table"):format(workspace, task_type)
      end

      local allowed_task_keys = {
        cmd = true,
      }

      if not has_only_allowed_keys(task_state, allowed_task_keys) then
        return nil, ("workspace `%s` task `%s` contains unsupported fields"):format(workspace, task_type)
      end

      local cmd = cmd_util.normalize(task_state.cmd)
      if not cmd then
        return nil, ("workspace `%s` task `%s` has invalid cmd"):format(workspace, task_type)
      end

      tasks[normalized_task_type] = {
        cmd = cmd_util.clone(cmd),
      }
    end

    if next(tasks) then
      sanitized.workspaces[workspace] = {
        tasks = tasks,
      }
    end
  end

  return sanitized, nil
end

---@param data qck.StorageState
---@return nil
local function write_data(data)
  local encoded = vim.json.encode(data)
  vim.fn.mkdir(vim.fn.fnamemodify(storage_path, ":h"), "p")
  vim.fn.writefile({ encoded }, storage_path)
end

---@return qck.StorageState, string|nil
local function read_data()
  if vim.fn.filereadable(storage_path) == 0 then
    return blank_state(), nil
  end

  local lines = vim.fn.readfile(storage_path)
  if not lines or #lines == 0 then
    return nil, "storage file is empty"
  end

  local decoded = vim.json.decode(table.concat(lines, "\n"))
  if type(decoded) ~= "table" then
    return nil, "storage file is not valid JSON object"
  end

  return decoded, nil
end

---@return boolean, string|nil
function storage.load()
  local ok_read, data_or_err, read_err = pcall(read_data)
  if not ok_read then
    storage.ok = false
    storage.workspaces = empty_map()
    storage.last_error = ("failed to read storage file: %s"):format(tostring(data_or_err))
    return false, storage.last_error
  end

  if read_err then
    storage.ok = false
    storage.workspaces = empty_map()
    storage.last_error = read_err
    return false, storage.last_error
  end

  local sanitized, sanitize_err = sanitize_data(data_or_err)
  if not sanitized then
    storage.ok = false
    storage.workspaces = empty_map()
    storage.last_error = sanitize_err or "failed to validate storage data"
    return false, storage.last_error
  end

  storage.ok = true
  storage.version = STORAGE_VERSION
  storage.workspaces = sanitized.workspaces
  storage.last_error = nil
  return true, nil
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
    storage.workspaces = empty_map()
  end

  if not storage.workspaces[workspace] then
    storage.workspaces[workspace] = {
      tasks = empty_map(),
    }
  end

  if type(storage.workspaces[workspace].tasks) ~= "table" then
    storage.workspaces[workspace].tasks = empty_map()
  end

  return storage.workspaces[workspace]
end

---@param workspace string
---@param task_type string
---@return qck.Command|nil
function storage.get_task_cmd(workspace, task_type)
  if not storage.ok or type(storage.workspaces) ~= "table" then
    return nil
  end

  if type(workspace) ~= "string" or workspace == "" then
    return nil
  end

  if type(task_type) ~= "string" then
    return nil
  end

  local normalized_task_type = vim.trim(task_type)
  if normalized_task_type == "" then
    return nil
  end

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.tasks) ~= "table" then
    return nil
  end

  local task = ws.tasks[normalized_task_type]
  if type(task) ~= "table" then
    return nil
  end

  local cmd = cmd_util.normalize(task.cmd)
  if not cmd then
    return nil
  end

  return cmd_util.clone(cmd)
end

---@param workspace string
---@return table<string, qck.Command>
function storage.get_workspace_tasks(workspace)
  if not storage.ok or type(storage.workspaces) ~= "table" then
    return {}
  end

  if type(workspace) ~= "string" or workspace == "" then
    return {}
  end

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.tasks) ~= "table" then
    return {}
  end

  local tasks = {}
  for task_type, task_state in pairs(ws.tasks) do
    if type(task_type) == "string" and type(task_state) == "table" then
      local normalized_task_type = vim.trim(task_type)
      local cmd = cmd_util.normalize(task_state.cmd)
      if normalized_task_type ~= "" and cmd then
        tasks[normalized_task_type] = cmd_util.clone(cmd)
      end
    end
  end

  return tasks
end

---@param workspace string
---@param task_type string
---@param cmd qck.Command
---@return nil
function storage.set_task_cmd(workspace, task_type, cmd)
  if not storage.ok then
    return
  end

  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  if type(task_type) ~= "string" then
    return
  end

  local normalized_task_type = vim.trim(task_type)
  if normalized_task_type == "" then
    return
  end

  local ws = storage.ensure_workspace(workspace)
  if not ws.tasks[normalized_task_type] then
    ws.tasks[normalized_task_type] = {}
  end

  ws.tasks[normalized_task_type].cmd = cmd_util.clone(cmd)
end

---@param workspace string
---@return nil
function storage.clear_workspace(workspace)
  if not storage.ok then
    return
  end

  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  storage.workspaces[workspace] = nil
end

return storage
