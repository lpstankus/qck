local agent_form = {}
local cmd_util = require("qck.shared.cmd")
local notify = require("qck.shared.notify").notify
local storage = require("qck.tasks.storage")
local text_form = require("qck.ui.form")

local TITLE = "QCK Set Agent"
local DESCRIPTION = "Please provide the command for the agent"
local HELP = "<CR> save  <Esc> close"
local CMD_PREFIX = "Command | "

local controller = text_form.create()

local state = {
  original_cmd = nil,
}

local function command_to_string(cmd)
  if type(cmd) == "table" then
    return table.concat(cmd, " ")
  end
  return tostring(cmd or "")
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
  state.original_cmd = nil
end

local function submit(values, form_controller)
  local normalized_cmd = command_for_submit(values.cmd or "")
  if not normalized_cmd then
    notify("agent command must not be empty", vim.log.levels.ERROR)
    form_controller.focus_field("cmd")
    return false
  end

  if storage.ok ~= true then
    notify(("workspace storage is unavailable: %s"):format(storage.last_error or "not loaded"), vim.log.levels.ERROR)
    return false
  end

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

  local cmd = storage.get_global_agent_cmd()
  state.original_cmd = cmd and cmd_util.clone(cmd) or nil
  controller.open({
    title = TITLE,
    description = DESCRIPTION,
    help = HELP,
    filetype = "qck-agent-form",
    fields = {
      { key = "cmd", prefix = CMD_PREFIX, value = cmd and command_to_string(cmd) or "" },
    },
    on_submit = submit,
    on_close = reset_agent_state,
  })
end

function agent_form.get_winid()
  return controller.get_winid()
end

return agent_form
