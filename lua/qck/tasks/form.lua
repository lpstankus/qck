local task_form = {}
local cmd_util = require("qck.shared.cmd")
local notify = require("qck.shared.notify").notify
local storage = require("qck.tasks.storage")
local terminal = require("qck.app.terminal")
local text_form = require("qck.ui.form")

local CREATE_TITLE = "QCK Create Task"
local EDIT_TITLE = "QCK Edit Task"
local CREATE_DESCRIPTION = "Please provide the name and command of the new task"
local EDIT_DESCRIPTION = "Please edit the name and command of the task"
local HELP = "<CR> next/save  <S-CR> prev  <Esc> close"
local NAME_PREFIX = "Name    | "
local CMD_PREFIX = "Command | "

local controller = text_form.create()

local state = {
  pending_overwrite_name = nil,
  pending_overwrite_cmd_key = nil,
  mode = "create",
  original_name = nil,
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

local function command_for_submit(raw_cmd)
  local normalized_cmd = cmd_util.normalize(vim.trim(raw_cmd))
  if not normalized_cmd then
    return nil
  end

  if state.mode == "edit"
    and state.original_cmd ~= nil
    and vim.trim(raw_cmd) == command_to_string(state.original_cmd)
  then
    return cmd_util.clone(state.original_cmd)
  end

  return normalized_cmd
end

local function command_key(cmd)
  if type(cmd) == "string" then
    return "s:" .. cmd
  end
  return "l:" .. vim.json.encode(cmd)
end

local function reset_task_state()
  state.pending_overwrite_name = nil
  state.pending_overwrite_cmd_key = nil
  state.mode = "create"
  state.original_name = nil
  state.original_cmd = nil
end

local function submit(values, form_controller)
  local name = vim.trim(values.name or "")
  local normalized_cmd = command_for_submit(values.cmd or "")

  if name == "" then
    notify("task name must not be empty", vim.log.levels.ERROR)
    state.pending_overwrite_name = nil
    form_controller.focus_field("name")
    return false
  end

  if not normalized_cmd then
    notify("task command must not be empty", vim.log.levels.ERROR)
    state.pending_overwrite_name = nil
    form_controller.focus_field("cmd")
    return false
  end

  local normalized_cmd_key = command_key(normalized_cmd)
  if state.pending_overwrite_name
    and (state.pending_overwrite_name ~= name or state.pending_overwrite_cmd_key ~= normalized_cmd_key)
  then
    state.pending_overwrite_name = nil
    state.pending_overwrite_cmd_key = nil
  end

  local workspace = current_workspace()
  local overwrite = false
  local original_name = state.original_name
  local is_editing_same_task = state.mode == "edit" and original_name == name
  if storage.get_task_cmd(workspace, name) ~= nil and not is_editing_same_task then
    if state.pending_overwrite_name ~= name then
      state.pending_overwrite_name = name
      state.pending_overwrite_cmd_key = normalized_cmd_key
      notify(("task `%s` already exists; press <CR> again to overwrite"):format(name), vim.log.levels.WARN)
      form_controller.focus_field("cmd")
      return false
    end
    overwrite = true
  end

  if storage.ok ~= true then
    notify(("workspace storage is unavailable: %s"):format(storage.last_error or "not loaded"), vim.log.levels.ERROR)
    return false
  end

  local previous_workspace_entries = storage.get_workspace_task_entries(workspace)
  local previous_agent_entries = storage.get_workspace_agent_entries(workspace)
  local previous_entry = storage.get_task_entry(workspace, name)
  local previous_original_entry = original_name and storage.get_task_entry(workspace, original_name) or nil
  local new_entry = {
    cmd = normalized_cmd,
    order = (state.mode == "edit" and previous_original_entry and previous_original_entry.order)
      or (previous_entry and previous_entry.order)
      or math.huge,
  }
  if state.mode == "edit" and original_name and original_name ~= name then
    storage.remove_task(workspace, original_name)
  end
  if new_entry.order == math.huge then
    storage.set_task_cmd(workspace, name, normalized_cmd)
  else
    storage.set_task_entry(workspace, name, new_entry)
  end

  local destructive_rename = state.mode == "edit" and original_name and original_name ~= name and overwrite
  if destructive_rename then
    storage.normalize_workspace_task_order(workspace)
  end

  local ok, err = storage.save()
  if not ok then
    storage.clear_workspace(workspace)
    for _, entry in ipairs(previous_workspace_entries) do
      storage.set_task_entry(workspace, entry.name, {
        cmd = entry.cmd,
        order = entry.order,
      })
    end
    for agent_type, entry in pairs(previous_agent_entries) do
      storage.set_agent_entry(workspace, agent_type, entry)
    end
    notify(("failed to save workspace task `%s`: %s"):format(name, err or "unknown error"), vim.log.levels.ERROR)
    return false
  end

  state.pending_overwrite_name = nil
  if state.mode == "edit" and original_name and original_name ~= name then
    terminal.refresh_renamed_task_identity(workspace, original_name, name)
  end

  local updated = overwrite or state.mode == "edit"
  notify((updated and "updated task `%s` for current workspace" or "created task `%s` for current workspace"):format(name), vim.log.levels.INFO)
  reset_task_state()
  return true
end

function task_form.close()
  controller.close()
  reset_task_state()
end

function task_form.submit()
  controller.submit()
end

local function open_form(mode, name, cmd)
  if controller.get_winid() then
    if mode == "edit" and (state.mode ~= "edit" or state.original_name ~= name) then
      task_form.close()
    else
      vim.api.nvim_set_current_win(controller.get_winid())
      controller.focus_current_field()
      return
    end
  end

  state.mode = mode
  state.original_name = mode == "edit" and name or nil
  state.original_cmd = mode == "edit" and cmd_util.clone(cmd) or nil
  state.pending_overwrite_name = nil
  state.pending_overwrite_cmd_key = nil

  controller.open({
    title = state.mode == "edit" and EDIT_TITLE or CREATE_TITLE,
    description = state.mode == "edit" and EDIT_DESCRIPTION or CREATE_DESCRIPTION,
    help = HELP,
    filetype = "qck-task-form",
    fields = {
      { key = "name", prefix = NAME_PREFIX, value = name or "" },
      { key = "cmd", prefix = CMD_PREFIX, value = command_to_string(cmd) },
    },
    on_submit = submit,
    on_close = reset_task_state,
  })
end

function task_form.open()
  open_form("create", "", "")
end

---@param name string
---@param cmd qck.Command
---@return nil
function task_form.open_edit(name, cmd)
  open_form("edit", vim.trim(name or ""), cmd)
end

function task_form.get_winid()
  return controller.get_winid()
end

return task_form
