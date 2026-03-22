local tasks = {}

local cmd_util = require("qck.shared.cmd")
local storage = require("qck.tasks.storage")

---@return string
local function current_workspace()
  return vim.fn.getcwd()
end

---@param task_type string
---@return string|nil
local function normalize_task_type(task_type)
  if type(task_type) ~= "string" then
    return nil
  end

  local normalized = vim.trim(task_type)
  if normalized == "" then
    return nil
  end

  return normalized
end

---@param task_type string
---@return boolean
function tasks.has_definition(task_type)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    return false
  end

  return storage.get_task_cmd(current_workspace(), normalized_task_type) ~= nil
end

---@param task_type string
---@param cmd qck.Command
---@param opts qck.CreateTaskOpts|nil
---@return boolean, string|nil, string|nil
function tasks.create_workspace_task(task_type, cmd, opts)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    return false, "invalid_task_type", nil
  end

  local normalized_cmd = cmd_util.normalize(cmd)
  if not normalized_cmd then
    return false, "invalid_cmd", nil
  end

  if storage.ok ~= true then
    return false, "storage_not_loaded", storage.last_error
  end

  local overwrite = opts and opts.overwrite == true
  local exists = tasks.has_definition(normalized_task_type)
  if exists and not overwrite then
    return false, "exists", nil
  end

  storage.set_task_cmd(current_workspace(), normalized_task_type, normalized_cmd)

  local ok_save, save_err = storage.save()
  if not ok_save then
    return false, "save_failed", save_err
  end

  return true, nil, nil
end

return tasks
