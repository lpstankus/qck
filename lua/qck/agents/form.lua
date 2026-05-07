local agent_form = {}
local cmd_util = require("qck.shared.cmd")
local notify = require("qck.shared.notify").notify
local storage = require("qck.tasks.storage")
local text_form = require("qck.ui.form")

local TITLE = "QCK Set Agent"
local DESCRIPTION = "Please provide the command for the agent"
local HELP = "<Tab> cycle scope  <CR> next/save  <S-CR> prev  <Esc> close"
local SCOPE_PREFIX = "Scope   | "
local CMD_PREFIX = "Command | "
local SCOPE_GLOBAL = "global"
local SCOPE_LOCAL = "local"

local controller = text_form.create()

local state = {
  scope = SCOPE_GLOBAL,
  original_cmd = nil,
}

local function current_workspace()
  return vim.fn.getcwd()
end

local function command_to_string(cmd)
  if type(cmd) == "table" then
    return table.concat(cmd, " ")
  end
  return tostring(cmd or "")
end

local function cmd_for_scope(scope)
  if scope == SCOPE_LOCAL then
    return storage.get_local_agent_cmd(current_workspace())
  end
  return storage.get_global_agent_cmd()
end

local function command_for_submit(raw_cmd)
  local normalized_cmd = cmd_util.normalize(vim.trim(raw_cmd))
  if not normalized_cmd then
    return nil
  end

  if state.original_cmd ~= nil and vim.trim(raw_cmd) == command_to_string(state.original_cmd) then
    return cmd_util.clone(state.original_cmd)
  end

  return normalized_cmd
end

local function reset_agent_state()
  state.scope = SCOPE_GLOBAL
  state.original_cmd = nil
end

local function restore_workspace_agents(workspace, previous_agent_entries)
  local ws = storage.workspaces[workspace]
  if type(ws) ~= "table" then
    if next(previous_agent_entries) == nil then
      return
    end
    ws = storage.ensure_workspace(workspace)
  end

  ws.agents = next(previous_agent_entries) and vim.deepcopy(previous_agent_entries) or vim.empty_dict()
  if (type(ws.tasks) ~= "table" or next(ws.tasks) == nil) and next(ws.agents) == nil then
    storage.workspaces[workspace] = nil
  end
end

local function submit_global(normalized_cmd)
  local previous_global_entries = storage.get_global_agent_entries()
  storage.set_global_agent_cmd(normalized_cmd)

  local ok, err = storage.save()
  if not ok then
    storage.agents = vim.deepcopy(previous_global_entries)
    notify(("failed to save agent: %s"):format(err or "unknown error"), vim.log.levels.ERROR)
    return false
  end

  notify("updated global agent", vim.log.levels.INFO)
  reset_agent_state()
  return true
end

local function submit_local(normalized_cmd)
  local workspace = current_workspace()
  local previous_agent_entries = storage.get_workspace_agent_entries(workspace)

  if normalized_cmd then
    storage.set_agent_cmd(workspace, normalized_cmd)
  else
    storage.remove_agent_cmd(workspace)
  end

  local ok, err = storage.save()
  if not ok then
    restore_workspace_agents(workspace, previous_agent_entries)
    notify(("failed to save agent: %s"):format(err or "unknown error"), vim.log.levels.ERROR)
    return false
  end

  notify(normalized_cmd and "updated local agent" or "removed local agent override", vim.log.levels.INFO)
  reset_agent_state()
  return true
end

local function submit(values, form_controller)
  local normalized_cmd = command_for_submit(values.cmd or "")
  if not normalized_cmd then
    if values.scope == SCOPE_LOCAL then
      if storage.ok ~= true then
        notify(("workspace storage is unavailable: %s"):format(storage.last_error or "not loaded"), vim.log.levels.ERROR)
        return false
      end
      return submit_local(nil)
    end

    notify("agent command must not be empty", vim.log.levels.ERROR)
    form_controller.focus_field("cmd")
    return false
  end

  if storage.ok ~= true then
    notify(("workspace storage is unavailable: %s"):format(storage.last_error or "not loaded"), vim.log.levels.ERROR)
    return false
  end

  if values.scope == SCOPE_LOCAL then
    return submit_local(normalized_cmd)
  end

  return submit_global(normalized_cmd)
end

local function refresh_scope(scope, form_controller)
  state.scope = scope == SCOPE_LOCAL and SCOPE_LOCAL or SCOPE_GLOBAL
  local cmd = cmd_for_scope(state.scope)
  state.original_cmd = cmd and cmd_util.clone(cmd) or nil
  form_controller.set_field_value("cmd", cmd and command_to_string(cmd) or "")
end

function agent_form.close()
  controller.close()
  reset_agent_state()
end

function agent_form.submit()
  controller.submit()
end

function agent_form.open()
  if controller.get_winid() then
    vim.api.nvim_set_current_win(controller.get_winid())
    controller.focus_current_field()
    return
  end

  local local_cmd = storage.get_local_agent_cmd(current_workspace())
  local scope = local_cmd and SCOPE_LOCAL or SCOPE_GLOBAL
  local cmd = local_cmd or storage.get_global_agent_cmd()
  state.scope = scope
  state.original_cmd = cmd and cmd_util.clone(cmd) or nil
  controller.open({
    title = TITLE,
    description = DESCRIPTION,
    help = HELP,
    filetype = "qck-agent-form",
    fields = {
      {
        key = "scope",
        prefix = SCOPE_PREFIX,
        type = "selection",
        value = scope,
        options = {
          { value = SCOPE_GLOBAL, label = "Global" },
          { value = SCOPE_LOCAL, label = "Local" },
        },
      },
      { key = "cmd", prefix = CMD_PREFIX, value = cmd and command_to_string(cmd) or "" },
    },
    on_submit = submit,
    on_change = function(key, value, form_controller)
      if key == "scope" then
        refresh_scope(value, form_controller)
      end
    end,
    on_close = reset_agent_state,
  })
end

function agent_form.get_winid()
  return controller.get_winid()
end

return agent_form
