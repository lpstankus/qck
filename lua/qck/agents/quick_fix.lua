local quick_fix = {}

local notify = require("qck.shared.notify").notify
local storage = require("qck.tasks.storage")
local terminal = require("qck.app.terminal")
local text_form = require("qck.ui.form")

local TITLE = "QCK Agent Quick Fix"
local controller = text_form.create()

local state = {
  reference = nil,
}

local function current_workspace()
  return vim.fn.getcwd()
end

---@param mode string
---@return boolean
local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == "\22"
end

---@return string|nil
local function selected_file_reference()
  local file = vim.fn.expand("%:p")
  if file == "" then
    return nil
  end

  local mode = vim.api.nvim_get_mode().mode
  local line_start = vim.fn.line(".")
  local line_end = line_start
  if is_visual_mode(mode) then
    line_start = vim.fn.line("v")
    line_end = vim.fn.line(".")
  end

  if line_start > line_end then
    line_start, line_end = line_end, line_start
  end

  local reference = ("%s:L%d"):format(file, line_start)
  if line_end ~= line_start then
    reference = ("%s-L%d"):format(reference, line_end)
  end
  return reference
end

---@param value string
---@return string
local function quote_arg(value)
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%$", "\\$"):gsub("`", "\\`") .. '"'
end

---@param cmd qck.Command
---@param prompt string
---@return qck.Command
local function build_agent_command(cmd, prompt)
  if type(cmd) == "table" then
    local parts = {}
    for idx, part in ipairs(cmd) do
      parts[idx] = part
    end
    parts[#parts + 1] = prompt
    return parts
  end

  return ("%s %s"):format(cmd, quote_arg(prompt))
end

local function reset_state()
  state.reference = nil
end

local function submit(values, form_controller)
  local message = vim.trim(values.message or "")
  if message == "" then
    notify("quick-fix message must not be empty", vim.log.levels.ERROR)
    form_controller.focus_field("message")
    return false
  end

  if type(state.reference) ~= "string" or state.reference == "" then
    notify("quick-fix agent requires a named file buffer", vim.log.levels.ERROR)
    form_controller.focus_field("message")
    return false
  end

  if storage.ok ~= true then
    notify(("workspace storage is unavailable: %s"):format(storage.last_error or "not loaded"), vim.log.levels.ERROR)
    return false
  end

  local workspace = current_workspace()
  local cmd = storage.get_agent_cmd(workspace)
  if not cmd then
    notify("no agent configured for current workspace", vim.log.levels.WARN)
    return false
  end

  local tab = terminal.create_agent_and_attach({
    workspace = workspace,
    cmd = build_agent_command(cmd, ("%s %s"):format(state.reference, message)),
    force_new = true,
  })
  if not tab then
    return false
  end

  reset_state()
  return true
end

function quick_fix.close()
  controller.close()
  reset_state()
end

function quick_fix.submit()
  controller.submit()
end

function quick_fix.open()
  if controller.get_winid() then
    vim.api.nvim_set_current_win(controller.get_winid())
    controller.focus_current_field()
    return
  end

  state.reference = selected_file_reference()
  controller.open({
    title = TITLE,
    description = "",
    help = "",
    filetype = "qck-agent-quick-fix-form",
    minimal = true,
    fields = {
      { key = "message", prefix = "", value = "" },
    },
    on_submit = submit,
    on_close = reset_state,
  })
end

function quick_fix.get_winid()
  return controller.get_winid()
end

return quick_fix
