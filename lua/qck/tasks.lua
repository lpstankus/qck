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
---@return qck.TaskDefinition|nil
local function get_task(task_type)
  return configured_tasks[task_type]
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
  local temp_cmd = cmd_util.normalize(temp_task_cmds[task_type])
  if temp_cmd then
    return cmd_util.clone(temp_cmd)
  end

  local stored_cmd = get_persistent_cmd(task_type)
  if stored_cmd then
    return cmd_util.clone(stored_cmd)
  end

  local task = get_task(task_type)
  if not task then
    return nil
  end

  return cmd_util.clone(task.cmd)
end

---@param task_type string
---@return integer|nil
local function find_running_id(task_type)
  return state.find_terminal_id_by_task_name(task_type)
end

---@param id integer
---@param task_type string
---@param opts table|nil
---@return qck.TerminalRecord|nil
local function spawn_task(id, task_type, opts)
  local task = get_task(task_type)
  if not task then
    return nil
  end

  local cmd = get_effective_cmd(task_type)
  if not cmd then
    notify(("task `%s` has no valid command"):format(task_type), vim.log.levels.ERROR)
    return nil
  end

  local create_opts = {
    kind = "task",
    cmd = cmd,
    task_name = task_type,
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
---@return boolean
local function ensure_task_type(task_type)
  if type(task_type) ~= "string" or vim.trim(task_type) == "" then
    notify("task type must be a non-empty string", vim.log.levels.ERROR)
    return false
  end

  if not get_task(task_type) then
    notify(("unknown task `%s`"):format(task_type), vim.log.levels.ERROR)
    return false
  end

  return true
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
  if not ensure_task_type(task_type) then
    return nil
  end

  local force_new = opts and opts.force_new == true
  local existing_id = find_running_id(task_type)

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

  return spawn_task(target_id, task_type, opts)
end

---@param task_type string
---@return qck.TerminalRecord|nil
function tasks.open(task_type)
  if not ensure_task_type(task_type) then
    return nil
  end

  local existing_id = get_running_id_or_warn(task_type)
  if not existing_id then
    return nil
  end

  return terminal.open(existing_id)
end

---@param task_type string
---@return nil
function tasks.toggle(task_type)
  if not ensure_task_type(task_type) then
    return
  end

  local existing_id = get_running_id_or_warn(task_type)
  if not existing_id then
    return
  end

  terminal.toggle(existing_id)
end

---@param task_type string
---@return nil
function tasks.kill(task_type)
  if not ensure_task_type(task_type) then
    return
  end

  local existing_id = get_running_id_or_warn(task_type)
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
  if not ensure_task_type(task_type) then
    return
  end

  local parsed_cmd = cmd_util.normalize(cmd)
  if not parsed_cmd then
    notify(("task `%s` command must be a non-empty string or list"):format(task_type), vim.log.levels.ERROR)
    return
  end

  if opts and opts.temp then
    temp_task_cmds[task_type] = cmd_util.clone(parsed_cmd)
    return
  end

  if not storage or type(storage.set_task_cmd) ~= "function" then
    notify("workspace storage is unavailable", vim.log.levels.ERROR)
    return
  end

  storage.set_task_cmd(current_workspace(), task_type, parsed_cmd)
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
  if not ensure_task_type(task_type) then
    return
  end

  if temp_task_cmds[task_type] then
    temp_task_cmds[task_type] = nil
    return
  end

  if not storage or type(storage.reset_task_cmd) ~= "function" then
    notify("workspace storage is unavailable", vim.log.levels.ERROR)
    return
  end

  storage.reset_task_cmd(current_workspace(), task_type)
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
    configured_tasks[task_type] = {
      cmd = cmd_util.clone(task.cmd),
      auto_scroll = task.auto_scroll,
    }
  end
end

---@param task_type string
---@return integer|nil
function tasks.get_running_id(task_type)
  if type(task_type) ~= "string" or vim.trim(task_type) == "" then
    return nil
  end
  return find_running_id(vim.trim(task_type))
end

return tasks
