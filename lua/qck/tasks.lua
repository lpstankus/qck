local tasks = {}
local state = require("qck.state")
local terminal = require("qck.terminal")
local cmd_util = require("qck.cmd")

local default_storage = require("qck.storage")

local configured_tasks = {}
local temp_task_cmds = {}
local storage = default_storage

---@param msg string
---@param level integer|nil
---@return nil
local function notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

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
---@return string|nil
local function find_task_key(task_type)
  local normalized = normalize_task_type(task_type)
  if not normalized then
    return nil
  end

  if configured_tasks[normalized] then
    return normalized
  end

  for existing_task_type in pairs(configured_tasks) do
    if normalize_task_type(existing_task_type) == normalized then
      return existing_task_type
    end
  end

  return nil
end

---@param task_type string
---@return qck.TaskDefinition|nil
local function get_task(task_type)
  local key = find_task_key(task_type)
  if not key then
    return nil
  end
  return configured_tasks[key]
end

---@param task_type string
---@return qck.Command|nil
local function get_persistent_cmd(task_type)
  if not storage or type(storage.get_task_cmd) ~= "function" then
    return nil
  end

  local cmd = storage.get_task_cmd(current_workspace(), task_type)
  return cmd_util.normalize(cmd)
end

---@param task_type string
---@return qck.Command|nil
local function get_effective_cmd(task_type)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    return nil
  end

  local temp_cmd = cmd_util.normalize(temp_task_cmds[normalized_task_type])
  if temp_cmd then
    return cmd_util.clone(temp_cmd)
  end

  local stored_cmd = get_persistent_cmd(normalized_task_type)
  if stored_cmd then
    return cmd_util.clone(stored_cmd)
  end

  local task = get_task(normalized_task_type)
  if not task then
    return nil
  end

  return cmd_util.clone(task.cmd)
end

---@param task_type string
---@return integer|nil
local function find_running_id(task_type)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    return nil
  end
  return state.find_terminal_id_by_task_name(normalized_task_type)
end

---@param id integer
---@param task_type string
---@param opts table|nil
---@return qck.TerminalRecord|nil
local function spawn_task(id, task_type, opts)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    return nil
  end

  local task = get_task(normalized_task_type)
  if not task then
    return nil
  end

  local cmd = get_effective_cmd(normalized_task_type)
  if not cmd then
    notify(("task `%s` has no valid command"):format(normalized_task_type), vim.log.levels.ERROR)
    return nil
  end

  local create_opts = {
    kind = "task",
    cmd = cmd,
    task_name = normalized_task_type,
    auto_scroll = opts and opts.auto_scroll,
  }

  if create_opts.auto_scroll == nil then
    create_opts.auto_scroll = task.auto_scroll
  end
  if create_opts.auto_scroll == nil then
    create_opts.auto_scroll = true
  end

  return terminal.create(id, create_opts)
end

---@param task_type string
---@return string|nil
local function ensure_task_type(task_type)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    notify("task type must be a non-empty string", vim.log.levels.ERROR)
    return nil
  end

  if not get_task(normalized_task_type) then
    notify(("unknown task `%s`"):format(normalized_task_type), vim.log.levels.ERROR)
    return nil
  end

  return normalized_task_type
end

---@param task_type string
---@return integer|nil
local function get_running_id_or_warn(task_type)
  local existing_id = find_running_id(task_type)
  if existing_id then
    return existing_id
  end

  notify(("task `%s` is not running"):format(task_type), vim.log.levels.WARN)
  return nil
end

---@param task_type string
---@param opts qck.TaskRunOpts|nil
---@return qck.TerminalRecord|nil
function tasks.run(task_type, opts)
  local normalized_task_type = ensure_task_type(task_type)
  if not normalized_task_type then
    return nil
  end

  local force_new = opts and opts.force_new == true
  local existing_id = find_running_id(normalized_task_type)

  if existing_id and not force_new then
    return terminal.open(existing_id)
  end

  local target_id = existing_id
  if existing_id and force_new then
    terminal.delete(existing_id)
    if state.get_terminal(existing_id) then
      return nil
    end
  end

  if not target_id then
    target_id = state.next_free_id()
  end

  return spawn_task(target_id, normalized_task_type, opts)
end

---@param task_type string
---@return qck.TerminalRecord|nil
function tasks.open(task_type)
  local normalized_task_type = ensure_task_type(task_type)
  if not normalized_task_type then
    return nil
  end

  local existing_id = get_running_id_or_warn(normalized_task_type)
  if not existing_id then
    return nil
  end

  return terminal.open(existing_id)
end

---@param task_type string
---@return nil
function tasks.toggle(task_type)
  local normalized_task_type = ensure_task_type(task_type)
  if not normalized_task_type then
    return
  end

  local existing_id = get_running_id_or_warn(normalized_task_type)
  if not existing_id then
    return
  end

  terminal.toggle(existing_id)
end

---@param task_type string
---@return nil
function tasks.kill(task_type)
  local normalized_task_type = ensure_task_type(task_type)
  if not normalized_task_type then
    return
  end

  local existing_id = get_running_id_or_warn(normalized_task_type)
  if not existing_id then
    return
  end

  terminal.delete(existing_id)
end

---@param task_type string
---@param cmd qck.Command
---@param opts { temp?: boolean }|nil
---@return nil
function tasks.set_task_cmd(task_type, cmd, opts)
  local normalized_task_type = ensure_task_type(task_type)
  if not normalized_task_type then
    return
  end

  local parsed_cmd = cmd_util.normalize(cmd)
  if not parsed_cmd then
    notify(
      ("task `%s` command must be a non-empty string or list"):format(normalized_task_type),
      vim.log.levels.ERROR
    )
    return
  end

  if opts and opts.temp then
    temp_task_cmds[normalized_task_type] = cmd_util.clone(parsed_cmd)
    return
  end

  if not storage or type(storage.set_task_cmd) ~= "function" then
    notify("workspace storage is unavailable", vim.log.levels.ERROR)
    return
  end

  storage.set_task_cmd(current_workspace(), normalized_task_type, parsed_cmd)
  if type(storage.save) == "function" then
    local ok, err = storage.save()
    if not ok then
      notify(
        ("failed to save workspace storage: %s"):format(err or "unknown error"),
        vim.log.levels.ERROR
      )
    end
  end
end

---@param task_type string
---@return nil
function tasks.reset_task_cmd(task_type)
  local normalized_task_type = ensure_task_type(task_type)
  if not normalized_task_type then
    return
  end

  if temp_task_cmds[normalized_task_type] then
    temp_task_cmds[normalized_task_type] = nil
    return
  end

  if not storage or type(storage.reset_task_cmd) ~= "function" then
    notify("workspace storage is unavailable", vim.log.levels.ERROR)
    return
  end

  storage.reset_task_cmd(current_workspace(), normalized_task_type)
  if type(storage.save) == "function" then
    local ok, err = storage.save()
    if not ok then
      notify(
        ("failed to save workspace storage: %s"):format(err or "unknown error"),
        vim.log.levels.ERROR
      )
    end
  end
end

---@param storage_impl table|nil
---@return nil
function tasks.set_storage(storage_impl)
  if type(storage_impl) ~= "table" then
    storage = default_storage
    return
  end

  storage = storage_impl
end

---@param definitions table<string, qck.TaskDefinition>
---@return nil
function tasks.set_definitions(definitions)
  configured_tasks = {}
  temp_task_cmds = {}

  for task_type, task in pairs(definitions or {}) do
    local normalized_task_type = normalize_task_type(task_type)
    local normalized_cmd = type(task) == "table" and cmd_util.normalize(task.cmd) or nil
    if normalized_task_type and normalized_cmd then
      configured_tasks[normalized_task_type] = {
        cmd = cmd_util.clone(normalized_cmd),
        auto_scroll = task.auto_scroll,
      }
    end
  end
end

---@param task_type string
---@return boolean
function tasks.has_definition(task_type)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    return false
  end

  return get_task(normalized_task_type) ~= nil
end

---@param workspace string|nil
---@return integer
function tasks.hydrate_workspace_tasks(workspace)
  if not storage or type(storage.get_workspace_tasks) ~= "function" then
    return 0
  end

  local target_workspace = workspace
  if type(target_workspace) ~= "string" or target_workspace == "" then
    target_workspace = current_workspace()
  end

  local workspace_tasks = storage.get_workspace_tasks(target_workspace)
  if type(workspace_tasks) ~= "table" then
    return 0
  end

  local added = 0
  for task_type, cmd in pairs(workspace_tasks) do
    local normalized_task_type = normalize_task_type(task_type)
    local normalized_cmd = cmd_util.normalize(cmd)
    if normalized_task_type and normalized_cmd and not tasks.has_definition(normalized_task_type) then
      configured_tasks[normalized_task_type] = {
        cmd = cmd_util.clone(normalized_cmd),
        auto_scroll = true,
      }
      added = added + 1
    end
  end

  return added
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

  local overwrite = opts and opts.overwrite == true
  local exists = tasks.has_definition(normalized_task_type)
  if exists and not overwrite then
    return false, "exists", nil
  end

  if not storage or type(storage.set_task_cmd) ~= "function" or type(storage.save) ~= "function" then
    return false, "storage_unavailable", nil
  end

  if storage.ok ~= true then
    return false, "storage_not_loaded", storage.last_error
  end

  local auto_scroll = true
  if type(opts and opts.auto_scroll) == "boolean" then
    auto_scroll = opts.auto_scroll
  end

  storage.set_task_cmd(current_workspace(), normalized_task_type, normalized_cmd)
  local ok_save, save_err = storage.save()
  if not ok_save then
    return false, "save_failed", save_err
  end

  if not exists then
    configured_tasks[normalized_task_type] = {
      cmd = cmd_util.clone(normalized_cmd),
      auto_scroll = auto_scroll,
    }
  end

  return true, nil, nil
end

---@param task_type string
---@return integer|nil
function tasks.get_running_id(task_type)
  local normalized_task_type = normalize_task_type(task_type)
  if not normalized_task_type then
    return nil
  end
  return find_running_id(normalized_task_type)
end

return tasks
