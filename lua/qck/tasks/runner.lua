local runner = {}
local autocmd = require("qck.shared.autocmd")
local notify = require("qck.shared.notify").notify
local task_form = require("qck.tasks.form")
local terminal = require("qck.app.terminal")
local storage = require("qck.tasks.storage")

local TITLE = "QCK Run Task"
local EMPTY_LINE = "No tasks for current workspace"
local DIVIDER = " │ "
local ns = vim.api.nvim_create_namespace("qck_task_runner")

vim.api.nvim_set_hl(0, "QckTaskRunnerCurrent", { reverse = true, default = true })

local state = {
  bufnr = nil,
  winid = nil,
  rows = {},
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

local function command_to_string(cmd)
  if type(cmd) == "table" then
    return table.concat(cmd, " ")
  end
  return tostring(cmd)
end

local function reset_state()
  for _, id in pairs(state.autocmd_ids) do
    autocmd.delete(id)
  end
  state.autocmd_ids = {}
  state.bufnr = nil
  state.winid = nil
  state.rows = {}
end

local function close()
  if is_valid_win(state.winid) then
    pcall(vim.api.nvim_win_close, state.winid, true)
  end
  reset_state()
end

local function build_rows()
  local entries = storage.get_workspace_task_entries(current_workspace())
  local rows = {}
  local max_name_width = 0
  local max_prefix_width = 0
  for index, entry in ipairs(entries) do
    max_name_width = math.max(max_name_width, #entry.name)
    max_prefix_width = math.max(max_prefix_width, #tostring(index) + 1)
  end

  for index, entry in ipairs(entries) do
    local number_prefix = ("%d."):format(index)
    rows[#rows + 1] = {
      name = entry.name,
      cmd = entry.cmd,
      order = entry.order,
      highlight_col = math.max(0, #number_prefix - 1),
      line = ("%s%s %s%s%s%s"):format(
        number_prefix,
        string.rep(" ", max_prefix_width - #number_prefix),
        entry.name,
        string.rep(" ", max_name_width - #entry.name),
        DIVIDER,
        command_to_string(entry.cmd)
      ),
    }
  end

  return rows
end

local function render()
  if not is_valid_buf(state.bufnr) then
    return
  end

  local lines = {}
  if #state.rows == 0 then
    lines[1] = EMPTY_LINE
  else
    for i, row in ipairs(state.rows) do
      lines[i] = row.line
    end
  end

  vim.bo[state.bufnr].modifiable = true
  vim.bo[state.bufnr].readonly = false
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
  vim.bo[state.bufnr].readonly = true
end

local function clamp_cursor()
  if not is_valid_win(state.winid) then
    return
  end

  local max_line = math.max(1, #state.rows)
  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  local line = math.min(math.max(cursor[1], 1), max_line)
  vim.api.nvim_win_set_cursor(state.winid, { line, 0 })
end

local function highlight_current()
  if not is_valid_buf(state.bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
  if #state.rows == 0 or not is_valid_win(state.winid) then
    return
  end

  clamp_cursor()
  local line = vim.api.nvim_win_get_cursor(state.winid)[1]
  local row = state.rows[line]
  vim.api.nvim_buf_set_extmark(state.bufnr, ns, line - 1, row and row.highlight_col or 0, {
    end_row = line,
    hl_group = "QckTaskRunnerCurrent",
    hl_eol = true,
  })
end

local function move_selection(delta)
  if not is_valid_win(state.winid) or #state.rows == 0 then
    return
  end

  local line = vim.api.nvim_win_get_cursor(state.winid)[1]
  line = math.min(math.max(line + delta, 1), #state.rows)
  vim.api.nvim_win_set_cursor(state.winid, { line, 0 })
  highlight_current()
end

local function move_task(delta)
  if not is_valid_win(state.winid) or #state.rows == 0 then
    return
  end

  clamp_cursor()
  local line = vim.api.nvim_win_get_cursor(state.winid)[1]
  local row = state.rows[line]
  if not row then
    return
  end

  local new_line = line + delta
  if new_line < 1 or new_line > #state.rows then
    return
  end

  local ok, err = storage.move_task_order(current_workspace(), row.name, delta)
  if not ok then
    notify(("failed to reorder task `%s`: %s"):format(row.name, err or "unknown error"), vim.log.levels.WARN)
    highlight_current()
    return
  end

  terminal.refresh_task_display_ids(current_workspace())
  state.rows = build_rows()
  render()
  vim.api.nvim_win_set_cursor(state.winid, { new_line, 0 })
  highlight_current()
end

---@param row table|nil
---@return boolean
local function run_row(row)
  if type(row) ~= "table" then
    return false
  end

  return terminal.create_task_and_attach({
    workspace = current_workspace(),
    name = row.name,
    cmd = row.cmd,
    order = row.order,
  }) ~= nil
end

local function select_current()
  if not is_valid_win(state.winid) or #state.rows == 0 then
    return
  end

  clamp_cursor()
  local line = vim.api.nvim_win_get_cursor(state.winid)[1]
  local row = state.rows[line]
  if not row then
    return
  end

  if run_row(row) then
    close()
  end
end

local function edit_current()
  if not is_valid_win(state.winid) or #state.rows == 0 then
    return
  end

  clamp_cursor()
  local line = vim.api.nvim_win_get_cursor(state.winid)[1]
  local row = state.rows[line]
  if not row then
    return
  end

  close()
  task_form.open_edit(row.name, row.cmd)
end

local function build_window_config()
  local width = math.max(40, math.floor(vim.o.columns * 0.45))
  local row_count = math.max(1, #state.rows)
  local height = math.min(math.max(1, row_count), math.max(1, vim.o.lines - 4))
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

local function set_window_options()
  if not is_valid_buf(state.bufnr) then
    return
  end

  vim.bo[state.bufnr].buftype = "nofile"
  vim.bo[state.bufnr].bufhidden = "wipe"
  vim.bo[state.bufnr].swapfile = false
  vim.bo[state.bufnr].filetype = "qck-task-runner"

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

local function block_insert()
  pcall(vim.cmd, "stopinsert")
end

local function apply_keymaps()
  if not is_valid_buf(state.bufnr) then
    return
  end

  local opts = { buffer = state.bufnr, noremap = true, silent = true }
  vim.keymap.set("n", "j", function() move_selection(1) end, opts)
  vim.keymap.set("n", "k", function() move_selection(-1) end, opts)
  vim.keymap.set("n", "J", function() move_task(1) end, opts)
  vim.keymap.set("n", "K", function() move_task(-1) end, opts)
  vim.keymap.set("n", "<CR>", select_current, opts)
  vim.keymap.set("n", "e", edit_current, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
  vim.keymap.set("n", "q", close, opts)

  for _, lhs in ipairs({ "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "r", "R" }) do
    vim.keymap.set("n", lhs, block_insert, opts)
  end
end

function runner.open()
  if is_valid_win(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    clamp_cursor()
    highlight_current()
    pcall(vim.cmd, "stopinsert")
    return
  end

  state.rows = build_rows()
  state.bufnr = vim.api.nvim_create_buf(false, true)
  state.winid = vim.api.nvim_open_win(state.bufnr, true, build_window_config())

  set_window_options()
  render()
  apply_keymaps()
  clamp_cursor()
  highlight_current()
  pcall(vim.cmd, "stopinsert")

  state.autocmd_ids.cursor = autocmd.create({ "CursorMoved", "WinEnter", "BufEnter" }, {
    buffer = state.bufnr,
    callback = function()
      clamp_cursor()
      highlight_current()
      pcall(vim.cmd, "stopinsert")
    end,
  })
  state.autocmd_ids.insert = autocmd.create("InsertEnter", {
    buffer = state.bufnr,
    callback = block_insert,
  })
  state.autocmd_ids.wipe = autocmd.create("BufWipeout", {
    buffer = state.bufnr,
    callback = reset_state,
    once = true,
  })
end

---@param task_number any
---@return nil
function runner.run_number(task_number)
  if type(task_number) ~= "number" or task_number < 1 or task_number % 1 ~= 0 then
    notify("run_task(number): task number must be a positive integer", vim.log.levels.WARN)
    return
  end

  local rows = build_rows()
  local row = rows[task_number]
  if not row then
    notify(("run_task(%d): no task at that position"):format(task_number), vim.log.levels.WARN)
    return
  end

  if run_row(row) then
    close()
  end
end

function runner.get_winid()
  if not is_valid_win(state.winid) then
    return nil
  end
  return state.winid
end

return runner
