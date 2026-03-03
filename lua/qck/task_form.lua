local task_form = {}
local tasks = require("qck.tasks")
local autocmd = require("qck.autocmd")

local TITLE = "QCK Create Task"
local DESCRIPTION = "Please provide the name and command of the new task"
local HELP = "<Tab>/<S-Tab> switch  <CR> save  <Esc> close"
local NAME_PREFIX = "Name    | "
local CMD_PREFIX = "Command | "
local MIN_SEPARATOR_WIDTH = 2048
local BAR_COL = NAME_PREFIX:find("|", 1, true)

local FIELDS = {
  { line = 3, prefix = NAME_PREFIX },
  { line = 4, prefix = CMD_PREFIX },
}

local state = {
  bufnr = nil,
  winid = nil,
  selected_field = 1,
  pending_overwrite_name = nil,
  is_sanitizing = false,
  autocmd_ids = {},
}

local function notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

local function is_valid_buf(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_win(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function in_insert_mode()
  local mode = vim.api.nvim_get_mode().mode
  return type(mode) == "string" and mode:sub(1, 1) == "i"
end

local function wrapped_field_idx(idx)
  return ((idx - 1) % #FIELDS) + 1
end

local function field(idx)
  return FIELDS[wrapped_field_idx(idx)]
end

local function reset_state()
  for _, id in pairs(state.autocmd_ids) do
    autocmd.delete(id)
  end
  state.autocmd_ids = {}
  state.bufnr = nil
  state.winid = nil
  state.selected_field = 1
  state.pending_overwrite_name = nil
  state.is_sanitizing = false
end

local function parse_field_value(field_def)
  if not is_valid_buf(state.bufnr) then
    return ""
  end

  local line = vim.api.nvim_buf_get_lines(state.bufnr, field_def.line - 1, field_def.line, false)[1] or ""
  if vim.startswith(line, field_def.prefix) then
    return line:sub(#field_def.prefix + 1)
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

local function set_field_value(field_def, value)
  if not is_valid_buf(state.bufnr) then
    return
  end
  vim.api.nvim_buf_set_lines(state.bufnr, field_def.line - 1, field_def.line, false, {
    field_def.prefix .. (value or ""),
  })
end

local function clamp_cursor_to_field()
  if not is_valid_win(state.winid) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  local line = cursor[1]
  local col = cursor[2]
  local target_line = line

  if line ~= field(1).line and line ~= field(2).line then
    target_line = field(state.selected_field).line
  end
  state.selected_field = target_line == field(1).line and 1 or 2

  local min_col = #field(state.selected_field).prefix
  if col < min_col then
    col = min_col
  end
  vim.api.nvim_win_set_cursor(state.winid, { target_line, col })
end

local function sanitize_buffer()
  if state.is_sanitizing or not is_valid_buf(state.bufnr) then
    return
  end

  state.is_sanitizing = true
  local name = parse_field_value(field(1))
  local cmd = parse_field_value(field(2))
  local sep_width = math.max(MIN_SEPARATOR_WIDTH, #NAME_PREFIX + math.max(#name, #cmd) + 64)
  local separator = string.rep("-", sep_width)
  if BAR_COL and BAR_COL <= sep_width then
    separator = separator:sub(1, BAR_COL - 1) .. "+" .. separator:sub(BAR_COL + 1)
  end

  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, {
    DESCRIPTION,
    separator,
    NAME_PREFIX .. name,
    CMD_PREFIX .. cmd,
    separator,
    HELP,
  })
  clamp_cursor_to_field()
  state.is_sanitizing = false
end

local function focus_field(field_idx)
  if not is_valid_win(state.winid) then
    return
  end
  local was_insert = in_insert_mode()
  sanitize_buffer()
  state.selected_field = wrapped_field_idx(field_idx)
  local selected = field(state.selected_field)
  vim.api.nvim_win_set_cursor(state.winid, { selected.line, #selected.prefix })
  if was_insert then
    vim.cmd("startinsert!")
  end
end

local function cycle_field(delta)
  focus_field(state.selected_field + delta)
end

local function is_on_command_field()
  if not is_valid_win(state.winid) then
    return false
  end
  return vim.api.nvim_win_get_cursor(state.winid)[1] == field(2).line
end

function task_form.close()
  if is_valid_win(state.winid) then
    pcall(vim.api.nvim_win_close, state.winid, true)
  end
  reset_state()
end

function task_form.submit()
  if not is_valid_win(state.winid) then
    return
  end

  sanitize_buffer()
  local name = vim.trim(parse_field_value(field(1)))
  local cmd = vim.trim(parse_field_value(field(2)))

  if name == "" then
    notify("task name must not be empty", vim.log.levels.ERROR)
    state.pending_overwrite_name = nil
    focus_field(1)
    return
  end

  if cmd == "" then
    notify("task command must not be empty", vim.log.levels.ERROR)
    state.pending_overwrite_name = nil
    focus_field(2)
    return
  end

  if state.pending_overwrite_name and state.pending_overwrite_name ~= name then
    state.pending_overwrite_name = nil
  end

  local overwrite = false
  if tasks.has_definition(name) then
    if state.pending_overwrite_name ~= name then
      state.pending_overwrite_name = name
      notify(("task `%s` already exists; press <CR> again to overwrite"):format(name), vim.log.levels.WARN)
      focus_field(2)
      return
    end
    overwrite = true
  end

  local ok, err, detail = tasks.create_workspace_task(name, cmd, { overwrite = overwrite })
  if not ok then
    if err == "storage_not_loaded" then
      notify(("workspace storage is unavailable: %s"):format(detail or "not loaded"), vim.log.levels.ERROR)
    elseif err == "save_failed" then
      notify(("failed to save workspace task `%s`: %s"):format(name, detail or "unknown error"), vim.log.levels.ERROR)
    elseif err == "exists" then
      notify(("task `%s` already exists"):format(name), vim.log.levels.ERROR)
    else
      notify(("failed to create task `%s` (%s)"):format(name, err or "unknown"), vim.log.levels.ERROR)
    end
    return
  end

  state.pending_overwrite_name = nil
  notify(
    (overwrite and "updated task `%s` for current workspace" or "created task `%s` for current workspace"):format(
      name
    ),
    vim.log.levels.INFO
  )
  task_form.close()
end

local function build_window_config()
  local width = math.max(50, math.floor(vim.o.columns * 0.5))
  local height = 6
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
  vim.bo[buf].filetype = "qck-task-form"
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
  vim.keymap.set({ "n", "i" }, "<Tab>", function() cycle_field(1) end, map_opts)
  vim.keymap.set({ "n", "i" }, "<S-Tab>", function() cycle_field(-1) end, map_opts)
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    if is_on_command_field() then
      task_form.submit()
      return
    end
    cycle_field(1)
  end, map_opts)
  vim.keymap.set("n", "<Esc>", function() task_form.close() end, map_opts)
end

function task_form.open()
  if is_valid_win(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    focus_field(state.selected_field)
    return
  end

  state.bufnr = vim.api.nvim_create_buf(false, true)
  state.winid = vim.api.nvim_open_win(state.bufnr, true, build_window_config())
  state.selected_field = 1
  state.pending_overwrite_name = nil

  set_window_options(state.bufnr)
  sanitize_buffer()
  apply_keymaps(state.bufnr)
  state.autocmd_ids.text = autocmd.create({ "TextChanged", "TextChangedI" }, {
    buffer = state.bufnr,
    callback = sanitize_buffer,
  })
  state.autocmd_ids.cursor = autocmd.create({ "CursorMoved", "CursorMovedI", "InsertEnter" }, {
    buffer = state.bufnr,
    callback = clamp_cursor_to_field,
  })
  state.autocmd_ids.wipe = autocmd.create("BufWipeout", {
    buffer = state.bufnr,
    callback = reset_state,
    once = true,
  })

  focus_field(1)
  vim.cmd("startinsert!")
end

function task_form.get_winid()
  if not is_valid_win(state.winid) then
    return nil
  end
  return state.winid
end

return task_form
