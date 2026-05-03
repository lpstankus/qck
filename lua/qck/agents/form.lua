local agent_form = {}
local autocmd = require("qck.shared.autocmd")
local cmd_util = require("qck.shared.cmd")
local notify = require("qck.shared.notify").notify
local storage = require("qck.tasks.storage")

local TITLE = "QCK Set Agent"
local DESCRIPTION = "Please provide the command for the workspace agent"
local HELP = "<CR> save  <Esc> close"
local CMD_PREFIX = "Command | "
local MIN_SEPARATOR_WIDTH = 2048
local BAR_COL = CMD_PREFIX:find("|", 1, true)

local state = {
  bufnr = nil,
  winid = nil,
  original_cmd = nil,
  is_sanitizing = false,
  autocmd_ids = {},
}

local function is_valid_buf(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_win(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function current_workspace()
  return vim.fn.getcwd()
end

local function reset_state()
  for _, id in pairs(state.autocmd_ids) do
    autocmd.delete(id)
  end
  state.autocmd_ids = {}
  state.bufnr = nil
  state.winid = nil
  state.original_cmd = nil
  state.is_sanitizing = false
end

local function parse_command()
  if not is_valid_buf(state.bufnr) then
    return ""
  end

  local line = vim.api.nvim_buf_get_lines(state.bufnr, 2, 3, false)[1] or ""
  if vim.startswith(line, CMD_PREFIX) then
    return line:sub(#CMD_PREFIX + 1)
  end

  local bar_pos = line:find("|", 1, true)
  if bar_pos then
    return line:sub(bar_pos + 1)
  end

  local labeled_value = line:match("^%s*[^:]+:%s*(.*)$")
  if labeled_value ~= nil then
    return labeled_value
  end

  return line
end

local function clamp_cursor_to_field()
  if not is_valid_win(state.winid) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  local col = math.max(cursor[2], #CMD_PREFIX)
  vim.api.nvim_win_set_cursor(state.winid, { 3, col })
end

local function sanitize_buffer()
  if state.is_sanitizing or not is_valid_buf(state.bufnr) then
    return
  end

  state.is_sanitizing = true
  local cmd = parse_command()
  local sep_width = math.max(MIN_SEPARATOR_WIDTH, #CMD_PREFIX + #cmd + 64)
  local separator = string.rep("-", sep_width)
  separator = separator:sub(1, BAR_COL - 1) .. "+" .. separator:sub(BAR_COL + 1)

  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, {
    DESCRIPTION,
    separator,
    CMD_PREFIX .. cmd,
    separator,
    HELP,
  })
  clamp_cursor_to_field()
  state.is_sanitizing = false
end

local function focus_command()
  if not is_valid_win(state.winid) then
    return
  end

  sanitize_buffer()
  vim.api.nvim_win_set_cursor(state.winid, { 3, #CMD_PREFIX })
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

  if state.original_cmd ~= nil and vim.trim(raw_cmd) == command_to_string(state.original_cmd) then
    return cmd_util.clone(state.original_cmd)
  end

  return normalized_cmd
end

function agent_form.close()
  if is_valid_win(state.winid) then
    pcall(vim.api.nvim_win_close, state.winid, true)
  end
  reset_state()
end

function agent_form.submit()
  if not is_valid_win(state.winid) then
    return
  end

  sanitize_buffer()
  local normalized_cmd = command_for_submit(parse_command())
  if not normalized_cmd then
    notify("agent command must not be empty", vim.log.levels.ERROR)
    focus_command()
    return
  end

  if storage.ok ~= true then
    notify(("workspace storage is unavailable: %s"):format(storage.last_error or "not loaded"), vim.log.levels.ERROR)
    return
  end

  local workspace = current_workspace()
  local previous_workspace_entries = storage.get_workspace_task_entries(workspace)
  local previous_entries = storage.get_workspace_agent_entries(workspace)
  storage.set_agent_cmd(workspace, normalized_cmd)

  local ok, err = storage.save()
  if not ok then
    storage.clear_workspace(workspace)
    for _, entry in ipairs(previous_workspace_entries) do
      storage.set_task_entry(workspace, entry.name, {
        cmd = entry.cmd,
        order = entry.order,
      })
    end
    for agent_type, entry in pairs(previous_entries) do
      storage.set_agent_entry(workspace, agent_type, entry)
    end
    notify(("failed to save workspace agent: %s"):format(err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  notify("updated workspace agent", vim.log.levels.INFO)
  agent_form.close()
end

local function build_window_config()
  local width = math.max(50, math.floor(vim.o.columns * 0.5))
  local height = 5
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    focusable = true,
    noautocmd = true,
    title = TITLE,
    title_pos = "center",
  }
end

local function set_window_options(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = "qck-agent-form"
  if not is_valid_win(state.winid) then
    return
  end
  vim.wo[state.winid].number = false
  vim.wo[state.winid].relativenumber = false
  vim.wo[state.winid].signcolumn = "no"
  vim.wo[state.winid].foldcolumn = "0"
  vim.wo[state.winid].cursorline = false
  vim.wo[state.winid].wrap = false
end

local function apply_keymaps(buf)
  local map_opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set({ "n", "i" }, "<CR>", function() agent_form.submit() end, map_opts)
  vim.keymap.set("n", "<Esc>", function() agent_form.close() end, map_opts)
end

function agent_form.open()
  if is_valid_win(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    focus_command()
    return
  end

  state.bufnr = vim.api.nvim_create_buf(false, true)
  state.winid = vim.api.nvim_open_win(state.bufnr, true, build_window_config())

  set_window_options(state.bufnr)
  local cmd = storage.get_agent_cmd(current_workspace())
  state.original_cmd = cmd and cmd_util.clone(cmd) or nil
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, {
    DESCRIPTION,
    "",
    CMD_PREFIX .. (cmd and (type(cmd) == "table" and table.concat(cmd, " ") or cmd) or ""),
    "",
    HELP,
  })
  sanitize_buffer()
  apply_keymaps(state.bufnr)
  focus_command()

  state.autocmd_ids.wipe = autocmd.create("BufWipeout", {
    buffer = state.bufnr,
    callback = reset_state,
    once = true,
  })
end

function agent_form.get_winid()
  if not is_valid_win(state.winid) then
    return nil
  end
  return state.winid
end

return agent_form
