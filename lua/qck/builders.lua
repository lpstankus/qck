local builders = {}
local state = require("qck.state")
local terminal = require("qck.terminal")
local cmd_util = require("qck.cmd")

local default_storage = require("qck.storage")

local configured_builders = {}
local temp_builder_cmds = {}
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

---@param builder_type string
---@return qck.BuilderDefinition|nil
local function get_builder(builder_type)
  return configured_builders[builder_type]
end

---@param builder_type string
---@return qck.Command|nil
local function get_persistent_cmd(builder_type)
  if not storage or type(storage.get_builder_cmd) ~= "function" then
    return nil
  end

  local cmd = storage.get_builder_cmd(current_workspace(), builder_type)
  return cmd_util.normalize(cmd)
end

---@param builder_type string
---@return qck.Command|nil
local function get_effective_cmd(builder_type)
  local temp_cmd = cmd_util.normalize(temp_builder_cmds[builder_type])
  if temp_cmd then
    return cmd_util.clone(temp_cmd)
  end

  local stored_cmd = get_persistent_cmd(builder_type)
  if stored_cmd then
    return cmd_util.clone(stored_cmd)
  end

  local builder = get_builder(builder_type)
  if not builder then
    return nil
  end

  return cmd_util.clone(builder.cmd)
end

---@param builder_type string
---@return integer|nil
local function find_running_id(builder_type)
  return state.find_terminal_id_by_builder_type(builder_type)
end

---@param id integer
---@param opts table|nil
---@return qck.TerminalRecord|nil
local function spawn_builder(id, builder_type, opts)
  local builder = get_builder(builder_type)
  if not builder then
    return nil
  end

  local cmd = get_effective_cmd(builder_type)
  if not cmd then
    notify(("builder `%s` has no valid command"):format(builder_type), vim.log.levels.ERROR)
    return nil
  end

  local create_opts = {
    kind = "long_running",
    cmd = cmd,
    builder_type = builder_type,
    auto_scroll = opts and opts.auto_scroll,
  }

  if create_opts.auto_scroll == nil then
    create_opts.auto_scroll = builder.auto_scroll
  end
  if create_opts.auto_scroll == nil then
    create_opts.auto_scroll = true
  end

  return terminal.create(id, create_opts)
end

---@param builder_type string
---@return boolean
local function ensure_builder_type(builder_type)
  if type(builder_type) ~= "string" or vim.trim(builder_type) == "" then
    notify("builder type must be a non-empty string", vim.log.levels.ERROR)
    return false
  end

  if not get_builder(builder_type) then
    notify(("unknown builder `%s`"):format(builder_type), vim.log.levels.ERROR)
    return false
  end

  return true
end

---@param builder_type string
---@return integer|nil
local function get_running_id_or_warn(builder_type)
  local existing_id = find_running_id(builder_type)
  if existing_id then
    return existing_id
  end

  notify(("builder `%s` is not running"):format(builder_type), vim.log.levels.WARN)
  return nil
end

---@param builder_type string
---@param opts qck.BuildOpts|nil
---@return qck.TerminalRecord|nil
function builders.build(builder_type, opts)
  if not ensure_builder_type(builder_type) then
    return nil
  end

  local force_new = opts and opts.force_new == true
  local existing_id = find_running_id(builder_type)

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

  return spawn_builder(target_id, builder_type, opts)
end

---@param builder_type string
---@return qck.TerminalRecord|nil
function builders.open(builder_type)
  if not ensure_builder_type(builder_type) then
    return nil
  end

  local existing_id = get_running_id_or_warn(builder_type)
  if not existing_id then
    return nil
  end

  return terminal.open(existing_id)
end

---@param builder_type string
---@return nil
function builders.toggle(builder_type)
  if not ensure_builder_type(builder_type) then
    return
  end

  local existing_id = get_running_id_or_warn(builder_type)
  if not existing_id then
    return
  end

  terminal.toggle(existing_id)
end

---@param builder_type string
---@return nil
function builders.kill(builder_type)
  if not ensure_builder_type(builder_type) then
    return
  end

  local existing_id = get_running_id_or_warn(builder_type)
  if not existing_id then
    return
  end

  terminal.delete(existing_id)
end

---@param builder_type string
---@param cmd qck.Command
---@param opts qck.SetBuilderCmdOpts|nil
---@return nil
function builders.set_builder_cmd(builder_type, cmd, opts)
  if not ensure_builder_type(builder_type) then
    return
  end

  local parsed_cmd = cmd_util.normalize(cmd)
  if not parsed_cmd then
    notify(("builder `%s` command must be a non-empty string or list"):format(builder_type), vim.log.levels.ERROR)
    return
  end

  if opts and opts.temp then
    temp_builder_cmds[builder_type] = cmd_util.clone(parsed_cmd)
    return
  end

  if not storage or type(storage.set_builder_cmd) ~= "function" then
    notify("workspace storage is unavailable", vim.log.levels.ERROR)
    return
  end

  storage.set_builder_cmd(current_workspace(), builder_type, parsed_cmd)
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

---@param builder_type string
---@return nil
function builders.reset_builder_cmd(builder_type)
  if not ensure_builder_type(builder_type) then
    return
  end

  if temp_builder_cmds[builder_type] then
    temp_builder_cmds[builder_type] = nil
    return
  end

  if not storage or type(storage.reset_builder_cmd) ~= "function" then
    notify("workspace storage is unavailable", vim.log.levels.ERROR)
    return
  end

  storage.reset_builder_cmd(current_workspace(), builder_type)
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
function builders.set_storage(storage_impl)
  if type(storage_impl) ~= "table" then
    storage = default_storage
    return
  end

  storage = storage_impl
end

---@param definitions table<string, qck.BuilderDefinition>
---@return nil
function builders.set_definitions(definitions)
  configured_builders = {}
  temp_builder_cmds = {}

  for builder_type, builder in pairs(definitions or {}) do
    configured_builders[builder_type] = {
      cmd = cmd_util.clone(builder.cmd),
      auto_scroll = builder.auto_scroll,
    }
  end
end

return builders
