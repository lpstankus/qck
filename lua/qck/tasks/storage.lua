local storage = {}
local cmd_util = require("qck.shared.cmd")

local STORAGE_VERSION = "0.1.0"
local DEFAULT_AGENT_KEY = "default"
local storage_path = vim.fn.stdpath("data") .. "/qck.json"

storage.ok = false
storage.version = STORAGE_VERSION
storage.agents = vim.empty_dict()
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
    agents = empty_map(),
    workspaces = empty_map(),
  }
end

---@param task qck.StorageTaskState
---@return qck.StorageTaskState
local function clone_task(task)
  return {
    cmd = cmd_util.clone(task.cmd),
    order = task.order,
  }
end

---@param agent qck.StorageAgentState
---@return qck.StorageAgentState
local function clone_agent(agent)
  return {
    cmd = cmd_util.clone(agent.cmd),
  }
end

---@param tasks table<string, qck.StorageTaskState>
---@return nil
local function normalize_task_order(tasks)
  local entries = {}
  for name, task in pairs(tasks) do
    entries[#entries + 1] = {
      name = name,
      order = type(task.order) == "number" and task.order or math.huge,
    }
  end

  table.sort(entries, function(left, right)
    if left.order == right.order then
      return left.name < right.name
    end
    return left.order < right.order
  end)

  for index, entry in ipairs(entries) do
    tasks[entry.name].order = index
  end
end

---@param agents table<string, any>
---@param context string
---@return table<string, qck.StorageAgentState>|nil, string|nil
local function sanitize_agents(agents, context)
  local sanitized_agents = {}
  for agent_type, agent_state in pairs(agents or {}) do
    if type(agent_type) ~= "string" then
      return nil, ("%s has non-string agent type key"):format(context)
    end

    local normalized_agent_type = vim.trim(agent_type)
    if normalized_agent_type == "" then
      return nil, ("%s has empty agent type key"):format(context)
    end

    if sanitized_agents[normalized_agent_type] then
      return nil, ("%s has duplicate agent `%s` after normalization"):format(context, normalized_agent_type)
    end

    if type(agent_state) ~= "table" then
      return nil, ("%s agent `%s` must be a table"):format(context, agent_type)
    end

    local allowed_agent_keys = {
      cmd = true,
    }

    if not has_only_allowed_keys(agent_state, allowed_agent_keys) then
      return nil, ("%s agent `%s` contains unsupported fields"):format(context, agent_type)
    end

    local cmd = cmd_util.normalize(agent_state.cmd)
    if not cmd then
      return nil, ("%s agent `%s` has invalid cmd"):format(context, agent_type)
    end

    sanitized_agents[normalized_agent_type] = {
      cmd = cmd_util.clone(cmd),
    }
  end

  return sanitized_agents, nil
end

---@param data any
---@return qck.StorageState|nil, string|nil
local function sanitize_data(data)
  if type(data) ~= "table" then
    return nil, "storage root must be a table"
  end

  local allowed_root_keys = {
    version = true,
    agents = true,
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
  if data.agents ~= nil and type(data.agents) ~= "table" then
    return nil, "storage agents must be a table"
  end

  local global_agents, global_agents_err = sanitize_agents(data.agents or {}, "storage")
  if not global_agents then
    return nil, global_agents_err
  end
  sanitized.agents = next(global_agents) and global_agents or empty_map()

  for workspace, ws in pairs(data.workspaces) do
    if type(workspace) ~= "string" or workspace == "" then
      return nil, "workspace keys must be non-empty strings"
    end

    if type(ws) ~= "table" then
      return nil, "workspace state must be a table"
    end

    local allowed_workspace_keys = {
      tasks = true,
      agents = true,
    }

    if not has_only_allowed_keys(ws, allowed_workspace_keys) then
      return nil, ("workspace `%s` contains unsupported fields"):format(workspace)
    end

    if ws.tasks ~= nil and type(ws.tasks) ~= "table" then
      return nil, ("workspace `%s`.tasks must be a table"):format(workspace)
    end

    local tasks = {}

    for task_type, task_state in pairs(ws.tasks or {}) do
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
        order = true,
      }

      if not has_only_allowed_keys(task_state, allowed_task_keys) then
        return nil, ("workspace `%s` task `%s` contains unsupported fields"):format(workspace, task_type)
      end

      if task_state.order ~= nil and (type(task_state.order) ~= "number" or task_state.order < 1 or task_state.order % 1 ~= 0) then
        return nil, ("workspace `%s` task `%s` has invalid order"):format(workspace, task_type)
      end

      local cmd = cmd_util.normalize(task_state.cmd)
      if not cmd then
        return nil, ("workspace `%s` task `%s` has invalid cmd"):format(workspace, task_type)
      end

      tasks[normalized_task_type] = {
        cmd = cmd_util.clone(cmd),
        order = task_state.order,
      }
    end

    if ws.agents ~= nil and type(ws.agents) ~= "table" then
      return nil, ("workspace `%s`.agents must be a table"):format(workspace)
    end

    local agents, agents_err = sanitize_agents(ws.agents or {}, ("workspace `%s`"):format(workspace))
    if not agents then
      return nil, agents_err
    end

    if next(tasks) or next(agents) then
      if next(tasks) then
        normalize_task_order(tasks)
      end
      sanitized.workspaces[workspace] = {
        tasks = next(tasks) and tasks or empty_map(),
        agents = next(agents) and agents or empty_map(),
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
    storage.agents = empty_map()
    storage.workspaces = empty_map()
    storage.last_error = ("failed to read storage file: %s"):format(tostring(data_or_err))
    return false, storage.last_error
  end

  if read_err then
    storage.ok = false
    storage.agents = empty_map()
    storage.workspaces = empty_map()
    storage.last_error = read_err
    return false, storage.last_error
  end

  local sanitized, sanitize_err = sanitize_data(data_or_err)
  if not sanitized then
    storage.ok = false
    storage.agents = empty_map()
    storage.workspaces = empty_map()
    storage.last_error = sanitize_err or "failed to validate storage data"
    return false, storage.last_error
  end

  storage.ok = true
  storage.version = STORAGE_VERSION
  storage.agents = sanitized.agents
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
    agents = storage.agents,
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
      agents = empty_map(),
    }
  end

  if type(storage.workspaces[workspace].tasks) ~= "table" then
    storage.workspaces[workspace].tasks = empty_map()
  end
  if type(storage.workspaces[workspace].agents) ~= "table" then
    storage.workspaces[workspace].agents = empty_map()
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
---@param task_type string
---@return qck.StorageTaskState|nil
function storage.get_task_entry(workspace, task_type)
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
  if not cmd or type(task.order) ~= "number" then
    return nil
  end

  return clone_task({ cmd = cmd, order = task.order })
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
---@return qck.StorageTaskEntry[]
function storage.get_workspace_task_entries(workspace)
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

  local entries = {}
  for task_type, task_state in pairs(ws.tasks) do
    if type(task_type) == "string" and type(task_state) == "table" then
      local normalized_task_type = vim.trim(task_type)
      local cmd = cmd_util.normalize(task_state.cmd)
      if normalized_task_type ~= "" and cmd and type(task_state.order) == "number" then
        entries[#entries + 1] = {
          name = normalized_task_type,
          cmd = cmd_util.clone(cmd),
          order = task_state.order,
        }
      end
    end
  end

  table.sort(entries, function(left, right)
    if left.order == right.order then
      return left.name < right.name
    end
    return left.order < right.order
  end)

  return entries
end

---@param workspace string
---@return nil
function storage.normalize_workspace_task_order(workspace)
  if not storage.ok or type(storage.workspaces) ~= "table" then
    return
  end

  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.tasks) ~= "table" then
    return
  end

  normalize_task_order(ws.tasks)
end

---@param tasks table<string, qck.StorageTaskState>
---@return integer
local function next_task_order(tasks)
  local max_order = 0
  for _, task in pairs(tasks) do
    if type(task) == "table" and type(task.order) == "number" then
      max_order = math.max(max_order, task.order)
    end
  end
  return max_order + 1
end

---@param workspace string
---@param task_type string
---@param task qck.StorageTaskState
---@return nil
function storage.set_task_entry(workspace, task_type, task)
  if not storage.ok then
    return
  end

  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  if type(task_type) ~= "string" or type(task) ~= "table" then
    return
  end

  local normalized_task_type = vim.trim(task_type)
  if normalized_task_type == "" then
    return
  end

  local cmd = cmd_util.normalize(task.cmd)
  if not cmd then
    return
  end

  local order = task.order
  if type(order) ~= "number" or order < 1 or order % 1 ~= 0 then
    return
  end

  local ws = storage.ensure_workspace(workspace)
  ws.tasks[normalized_task_type] = {
    cmd = cmd_util.clone(cmd),
    order = order,
  }
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
    ws.tasks[normalized_task_type] = {
      order = next_task_order(ws.tasks),
    }
  end

  ws.tasks[normalized_task_type].cmd = cmd_util.clone(cmd)
end

---@param workspace string
---@return qck.Command|nil
function storage.get_local_agent_cmd(workspace)
  if not storage.ok or type(storage.workspaces) ~= "table" then
    return nil
  end

  if type(workspace) ~= "string" or workspace == "" then
    return nil
  end

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.agents) ~= "table" then
    return nil
  end

  local agent = ws.agents[DEFAULT_AGENT_KEY]
  if type(agent) ~= "table" then
    return nil
  end

  local cmd = cmd_util.normalize(agent.cmd)
  if not cmd then
    return nil
  end

  return cmd_util.clone(cmd)
end

---@return qck.Command|nil
function storage.get_global_agent_cmd()
  if not storage.ok or type(storage.agents) ~= "table" then
    return nil
  end

  local agent = storage.agents[DEFAULT_AGENT_KEY]
  if type(agent) ~= "table" then
    return nil
  end

  local cmd = cmd_util.normalize(agent.cmd)
  if not cmd then
    return nil
  end

  return cmd_util.clone(cmd)
end

---@param workspace string
---@return qck.Command|nil
function storage.get_agent_cmd(workspace)
  return storage.get_local_agent_cmd(workspace) or storage.get_global_agent_cmd()
end

---@param workspace string
---@return qck.StorageAgentState|nil
function storage.get_agent_entry(workspace)
  local cmd = storage.get_local_agent_cmd(workspace)
  if not cmd then
    return nil
  end

  return clone_agent({ cmd = cmd })
end

---@return table<string, qck.StorageAgentState>
function storage.get_global_agent_entries()
  if not storage.ok or type(storage.agents) ~= "table" then
    return empty_map()
  end

  local agents = empty_map()
  for agent_type, agent_state in pairs(storage.agents) do
    if type(agent_type) == "string" and type(agent_state) == "table" then
      local normalized_agent_type = vim.trim(agent_type)
      local cmd = cmd_util.normalize(agent_state.cmd)
      if normalized_agent_type ~= "" and cmd then
        agents[normalized_agent_type] = {
          cmd = cmd_util.clone(cmd),
        }
      end
    end
  end

  return agents
end

---@param workspace string
---@return table<string, qck.StorageAgentState>
function storage.get_workspace_agent_entries(workspace)
  if not storage.ok or type(storage.workspaces) ~= "table" then
    return {}
  end

  if type(workspace) ~= "string" or workspace == "" then
    return {}
  end

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.agents) ~= "table" then
    return {}
  end

  local agents = {}
  for agent_type, agent_state in pairs(ws.agents) do
    if type(agent_type) == "string" and type(agent_state) == "table" then
      local normalized_agent_type = vim.trim(agent_type)
      local cmd = cmd_util.normalize(agent_state.cmd)
      if normalized_agent_type ~= "" and cmd then
        agents[normalized_agent_type] = {
          cmd = cmd_util.clone(cmd),
        }
      end
    end
  end

  return agents
end

---@param agent_type string
---@param agent qck.StorageAgentState
---@return nil
function storage.set_global_agent_entry(agent_type, agent)
  if not storage.ok then
    return
  end

  if type(agent_type) ~= "string" or type(agent) ~= "table" then
    return
  end

  local normalized_agent_type = vim.trim(agent_type)
  if normalized_agent_type == "" then
    return
  end

  local normalized_cmd = cmd_util.normalize(agent.cmd)
  if not normalized_cmd then
    return
  end

  if type(storage.agents) ~= "table" then
    storage.agents = empty_map()
  end

  storage.agents[normalized_agent_type] = {
    cmd = cmd_util.clone(normalized_cmd),
  }
end

---@param cmd qck.Command
---@return nil
function storage.set_global_agent_cmd(cmd)
  storage.set_global_agent_entry(DEFAULT_AGENT_KEY, { cmd = cmd })
end

---@param workspace string
---@param agent_type string
---@param agent qck.StorageAgentState
---@return nil
function storage.set_agent_entry(workspace, agent_type, agent)
  if not storage.ok then
    return
  end

  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  if type(agent_type) ~= "string" or type(agent) ~= "table" then
    return
  end

  local normalized_agent_type = vim.trim(agent_type)
  if normalized_agent_type == "" then
    return
  end

  local normalized_cmd = cmd_util.normalize(agent.cmd)
  if not normalized_cmd then
    return
  end

  local ws = storage.ensure_workspace(workspace)
  ws.agents[normalized_agent_type] = {
    cmd = cmd_util.clone(normalized_cmd),
  }
end

---@param workspace string
---@param cmd qck.Command
---@return nil
function storage.set_agent_cmd(workspace, cmd)
  storage.set_agent_entry(workspace, DEFAULT_AGENT_KEY, { cmd = cmd })
end

---@param workspace string
---@param task_type string
---@param delta integer
---@return boolean, string|nil
function storage.move_task_order(workspace, task_type, delta)
  if not storage.ok then
    return false, "storage is not loaded"
  end

  if type(workspace) ~= "string" or workspace == "" then
    return false, "invalid workspace"
  end

  if type(task_type) ~= "string" then
    return false, "invalid task"
  end

  local normalized_task_type = vim.trim(task_type)
  if normalized_task_type == "" then
    return false, "invalid task"
  end

  if delta ~= -1 and delta ~= 1 then
    return false, "invalid direction"
  end

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.tasks) ~= "table" then
    return false, "workspace has no tasks"
  end

  local entries = storage.get_workspace_task_entries(workspace)
  local source_index = nil
  for index, entry in ipairs(entries) do
    if entry.name == normalized_task_type then
      source_index = index
      break
    end
  end

  if not source_index then
    return false, "task not found"
  end

  local target_index = source_index + delta
  if target_index < 1 or target_index > #entries then
    return false, "task is already at boundary"
  end

  local source = entries[source_index]
  local target = entries[target_index]
  local source_task = ws.tasks[source.name]
  local target_task = ws.tasks[target.name]
  if type(source_task) ~= "table" or type(target_task) ~= "table" then
    return false, "task not found"
  end

  local source_order = source_task.order
  local target_order = target_task.order
  source_task.order = target_order
  target_task.order = source_order

  local ok_save, save_err = storage.save()
  if not ok_save then
    source_task.order = source_order
    target_task.order = target_order
    return false, save_err
  end

  return true, nil
end

---@param workspace string
---@param task_type string
---@return nil
function storage.remove_task(workspace, task_type)
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

  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" or type(ws.tasks) ~= "table" then
    return
  end

  ws.tasks[normalized_task_type] = nil
  if next(ws.tasks) == nil and (type(ws.agents) ~= "table" or next(ws.agents) == nil) then
    storage.workspaces[workspace] = nil
  end
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
