local helpers = require("helpers")

local scenarios = {}

local function trim_lines(lines)
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = vim.trim(line)
  end
  return out
end

local function assert_ids(actual, expected, msg)
  helpers.assert_truthy(vim.deep_equal(actual, expected), msg)
end

local function assert_cmd(actual, expected, msg)
  helpers.assert_truthy(vim.deep_equal(actual, expected), msg)
end

local function tabbar_labels(tabbar_win)
  local buf = vim.api.nvim_win_get_buf(tabbar_win)
  return trim_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

local function tabbar_divider_label(tabbar_win)
  return string.rep("─", vim.api.nvim_win_get_width(tabbar_win))
end

---@param handle table|nil
---@return boolean
local function handle_is_open(handle)
  return type(handle) == "table" and type(handle.valid) == "function" and handle:valid()
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
  vim.wait(20, function() return false end)
end

---@param bufnr integer
---@param mode string
---@param lhs string
---@return boolean
local function buf_has_mapping(bufnr, mode, lhs)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
    if mapping.lhs == lhs then
      return true
    end
  end

  return false
end

---@param mode string
---@param msg string
local function assert_terminal_mode(mode, msg)
  helpers.assert_truthy(type(mode) == "string" and mode:find("t", 1, true) ~= nil, msg)
end

local function window_title(winid)
  local title = vim.api.nvim_win_get_config(winid).title
  if type(title) == "string" then
    return title
  end

  if type(title) == "table" then
    local parts = {}
    for _, chunk in ipairs(title) do
      if type(chunk) == "string" then
        parts[#parts + 1] = chunk
      elseif type(chunk) == "table" and type(chunk[1]) == "string" then
        parts[#parts + 1] = chunk[1]
      end
    end
    return table.concat(parts, "")
  end

  return ""
end

---@param handle table
local function attach_terminal_job(handle)
  helpers.assert_truthy(handle and type(handle.win) == "number", "terminal test handle should have a window")
  vim.api.nvim_set_current_win(handle.win)
  vim.bo[handle.buf].modifiable = true
  vim.api.nvim_buf_set_lines(handle.buf, 0, -1, false, {})
  vim.bo[handle.buf].modified = false
  local job_id = vim.fn.termopen({ "sh", "-c", "cat" })
  helpers.assert_truthy(type(job_id) == "number" and job_id > 0, "terminal test buffer should start a terminal job")
end

---@param matcher fun(item: table): boolean
---@return boolean
local function any_qck_autocmd(matcher)
  for _, item in ipairs(vim.api.nvim_get_autocmds({ group = "qck" })) do
    if matcher(item) then
      return true
    end
  end

  return false
end

function scenarios.task_form_create_and_overwrite()
  local env = helpers.load_qck()
  local qck, storage, task_form, workspace =
    env.qck, env.storage, env.task_form, env.workspace
  local original_notify = vim.notify

  vim.notify = function() end

  local ok, err = pcall(function()

    qck.new_task()
    local form_win = task_form.get_winid()
    helpers.assert_truthy(type(form_win) == "number", "new_task() should open task form window")

    qck.new_task()
    helpers.assert_eq(task_form.get_winid(), form_win, "new_task() should focus existing task form window")

    local form_buf = vim.api.nvim_win_get_buf(form_win)
    helpers.assert_eq(vim.bo[form_buf].filetype, "qck-task-form", "task form should set filetype")
    helpers.assert_form_scaffold(form_buf)

    helpers.set_form_fields(form_buf, "Name: lint", "Command: echo lint")
    task_form.submit()
    helpers.assert_eq(task_form.get_winid(), nil, "task form should close after successful create")
    helpers.assert_eq(storage.get_task_cmd(workspace, "lint"), "echo lint", "created task command should persist")

    qck.new_task()
    form_win = task_form.get_winid()
    helpers.assert_truthy(type(form_win) == "number", "second new_task() should open task form")

    form_buf = vim.api.nvim_win_get_buf(form_win)
    helpers.set_form_fields(form_buf, "Name: lint", "Command: echo lint 2")
    task_form.submit()
    helpers.assert_truthy(task_form.get_winid() ~= nil, "first duplicate save should require confirmation")
    helpers.assert_eq(
      storage.get_task_cmd(workspace, "lint"),
      "echo lint",
      "first duplicate save should not overwrite existing task"
    )

    form_buf = vim.api.nvim_win_get_buf(task_form.get_winid())
    helpers.set_form_fields(form_buf, "Name: ", "Command: echo lint 2")
    task_form.submit()
    helpers.assert_truthy(task_form.get_winid() ~= nil, "empty name validation should keep task form open")

    helpers.set_form_fields(form_buf, "Name: lint", "Command: echo lint 2")
    task_form.submit()
    helpers.assert_truthy(
      task_form.get_winid() ~= nil,
      "changing form contents after duplicate warning should require overwrite confirmation again"
    )
    helpers.assert_eq(
      storage.get_task_cmd(workspace, "lint"),
      "echo lint",
      "duplicate overwrite confirmation should not persist before second submit"
    )

    task_form.submit()
    helpers.assert_eq(task_form.get_winid(), nil, "second duplicate save should close task form")
    helpers.assert_eq(
      storage.get_task_cmd(workspace, "lint"),
      "echo lint 2",
      "second duplicate save should overwrite existing task"
    )
    helpers.assert_eq(
      storage.get_task_cmd(workspace .. "-other", "lint"),
      nil,
      "task form should only persist to the current workspace"
    )
  end)

  vim.notify = original_notify
  if not ok then
    error(err)
  end
end

function scenarios.task_form_edit_existing_task()
  local env = helpers.load_qck()
  local storage, task_form, workspace =
    env.storage, env.task_form, env.workspace
  local original_notify = vim.notify

  vim.notify = function() end

  local ok, err = pcall(function()
    storage.set_task_cmd(workspace, "lint", "echo lint")
    storage.set_task_cmd(workspace, "test", "echo test")

    task_form.open()
    local create_win = task_form.get_winid()
    helpers.assert_truthy(type(create_win) == "number", "create form should open before edit replacement coverage")

    task_form.open_edit("lint", "echo lint")
    local form_win = task_form.get_winid()
    helpers.assert_truthy(type(form_win) == "number", "open_edit() should open task form")
    helpers.assert_truthy(form_win ~= create_win, "open_edit() should replace an existing create form")
    helpers.assert_eq(window_title(form_win), "QCK Edit Task", "edit form should use edit title")

    local form_buf = vim.api.nvim_win_get_buf(form_win)
    helpers.assert_form_scaffold(form_buf, "Please edit the name and command of the task")
    local lines = vim.api.nvim_buf_get_lines(form_buf, 0, -1, false)
    helpers.assert_eq(lines[3], "Name    | lint", "edit form should prefill task name")
    helpers.assert_eq(lines[4], "Command | echo lint", "edit form should prefill task command")

    helpers.set_form_fields(form_buf, "Name: lint", "Command: echo lint --fix")
    task_form.submit()
    helpers.assert_eq(task_form.get_winid(), nil, "command-only edit should close form")
    helpers.assert_eq(storage.get_task_cmd(workspace, "lint"), "echo lint --fix", "command-only edit should update original task")

    task_form.open_edit("lint", "echo lint --fix")
    form_buf = vim.api.nvim_win_get_buf(task_form.get_winid())
    helpers.set_form_fields(form_buf, "Name: check", "Command: echo check")
    task_form.submit()
    helpers.assert_eq(task_form.get_winid(), nil, "rename edit should close form")
    helpers.assert_eq(storage.get_task_cmd(workspace, "lint"), nil, "rename edit should remove original task name")
    helpers.assert_eq(storage.get_task_cmd(workspace, "check"), "echo check", "rename edit should save new task name")

    task_form.open_edit("check", "echo check")
    form_buf = vim.api.nvim_win_get_buf(task_form.get_winid())
    helpers.set_form_fields(form_buf, "Name: test", "Command: echo overwritten")
    task_form.submit()
    helpers.assert_truthy(task_form.get_winid() ~= nil, "rename collision should require overwrite confirmation")
    helpers.assert_eq(storage.get_task_cmd(workspace, "check"), "echo check", "rename collision should keep original before confirmation")
    helpers.assert_eq(storage.get_task_cmd(workspace, "test"), "echo test", "rename collision should keep target before confirmation")

    helpers.set_form_fields(form_buf, "Name: test", "Command: echo changed again")
    task_form.submit()
    helpers.assert_truthy(
      task_form.get_winid() ~= nil,
      "changing command after rename collision warning should require overwrite confirmation again"
    )
    helpers.assert_eq(storage.get_task_cmd(workspace, "check"), "echo check", "changed rename collision should keep original before confirmation")
    helpers.assert_eq(storage.get_task_cmd(workspace, "test"), "echo test", "changed rename collision should keep target before confirmation")

    task_form.submit()
    helpers.assert_eq(task_form.get_winid(), nil, "confirmed rename collision should close form")
    helpers.assert_eq(storage.get_task_cmd(workspace, "check"), nil, "confirmed rename collision should remove original")
    helpers.assert_eq(storage.get_task_cmd(workspace, "test"), "echo changed again", "confirmed rename collision should overwrite target with changed command")

    storage.set_task_cmd(workspace, "old", "echo old")
    storage.set_task_cmd(workspace, "target", "echo target")
    task_form.open_edit("old", "echo old")
    form_buf = vim.api.nvim_win_get_buf(task_form.get_winid())
    helpers.set_form_fields(form_buf, "Name: target", "Command: echo failed")
    task_form.submit()
    local original_save = storage.save
    storage.save = function()
      return false, "forced failure"
    end
    task_form.submit()
    storage.save = original_save
    helpers.assert_truthy(task_form.get_winid() ~= nil, "failed edit save should keep form open")
    helpers.assert_eq(storage.get_task_cmd(workspace, "old"), "echo old", "failed rename save should restore original task")
    helpers.assert_eq(storage.get_task_cmd(workspace, "target"), "echo target", "failed rename save should restore target task")
    task_form.close()

    storage.set_task_cmd(workspace, "build", { "sh", "-c", "echo build" })
    task_form.open_edit("build", { "sh", "-c", "echo build" })
    task_form.submit()
    helpers.assert_truthy(
      vim.deep_equal(storage.get_task_cmd(workspace, "build"), { "sh", "-c", "echo build" }),
      "unchanged structured edit command should preserve command list form"
    )
  end)

  vim.notify = original_notify
  if not ok then
    error(err)
  end
end

function scenarios.task_runner_selects_workspace_task()
  local env = helpers.load_qck()
  local qck, storage, task_runner, ui_state, tabbar, workspace =
    env.qck, env.storage, env.task_runner, env.ui_state, env.tabbar, env.workspace
  local ui_runtime = require("qck.ui.runtime")
  local other_workspace = workspace .. "-other"
  local notifications = {}
  local original_notify = vim.notify

  storage.set_task_cmd(workspace, "lint", "echo lint")
  storage.set_task_cmd(workspace, "test", { "sh", "-c", "echo qck-task" })
  storage.set_task_cmd(other_workspace, "build", "echo build")

  vim.notify = function(msg, level)
    notifications[#notifications + 1] = { msg = msg, level = level }
  end

  local ok, err = pcall(function()
    qck.run_task()
    local runner_win = task_runner.get_winid()
    helpers.assert_truthy(type(runner_win) == "number", "run_task() should open task runner window")

    qck.run_task()
    helpers.assert_eq(task_runner.get_winid(), runner_win, "run_task() should focus existing task runner window")

    local runner_buf = vim.api.nvim_win_get_buf(runner_win)
    helpers.assert_eq(vim.bo[runner_buf].filetype, "qck-task-runner", "task runner should set filetype")
    helpers.assert_truthy(vim.bo[runner_buf].modifiable == false, "task runner buffer should not be modifiable")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "j"), "task runner should map j")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "k"), "task runner should map k")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "J"), "task runner should map J")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "K"), "task runner should map K")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "<CR>"), "task runner should map <CR>")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "<Esc>"), "task runner should map <Esc>")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "q"), "task runner should map q")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "e"), "task runner should map e")
    helpers.assert_truthy(buf_has_mapping(runner_buf, "n", "i"), "task runner should block insert entry")

    local lines = vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false)
    helpers.assert_truthy(
      vim.deep_equal(lines, { "1. lint │ echo lint", "2. test │ sh -c echo qck-task" }),
      "task runner should render current workspace tasks with order numbers and divider"
    )

    local current_line = vim.api.nvim_win_get_cursor(runner_win)[1]
    helpers.assert_eq(current_line, 1, "task runner should start on first task")
    local marks = vim.api.nvim_buf_get_extmarks(runner_buf, -1, 0, -1, { details = true })
    helpers.assert_eq(#marks, 1, "task runner should highlight the selected line")
    helpers.assert_eq(marks[1][2], 0, "task runner highlight should start on current line")
    helpers.assert_eq(marks[1][3], 1, "task runner highlight should leave the number unhighlighted")
    helpers.assert_truthy(marks[1][4].hl_group == "QckTaskRunnerCurrent", "task runner should use its current-row highlight")
    helpers.assert_truthy(marks[1][4].hl_eol == true, "task runner should highlight the selected row after the number")

    feed("j")
    helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 2, "j should move selection down")
    feed("j")
    helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 2, "j should stop at the last task")
    feed("k")
    helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 1, "k should move selection up")
    feed("k")
    helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 1, "k should stop at the first task")

    feed("i")
    helpers.assert_truthy(vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i", "task runner should not allow insert mode")
    helpers.assert_truthy(vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), lines), "blocked insert should not mutate runner rows")

    feed("q")
    helpers.assert_eq(task_runner.get_winid(), nil, "q should close the task runner")

    qck.run_task()
    runner_win = task_runner.get_winid()
    helpers.assert_truthy(type(runner_win) == "number", "run_task() should reopen task runner after q closes it")

    feed("j")
    feed("<CR>")
    helpers.assert_eq(#notifications, 0, "<CR> should not emit validation-only task notifications")
    helpers.assert_eq(task_runner.get_winid(), nil, "<CR> should close the task runner after spawning a task terminal")

    local active_tab_id = ui_state.resolve_active_tab()
    local active_tab = active_tab_id and ui_state.get_tab(active_tab_id) or nil
    local handle = active_tab and active_tab.terminal or nil
    helpers.assert_truthy(active_tab_id ~= nil, "<CR> should create an active task tab")
    helpers.assert_eq(active_tab and active_tab.category_key, "task", "task runner should attach selected tasks to the task category")
    helpers.assert_eq(active_tab and active_tab.category_label, "K", "task runner should label task terminals as K")
    helpers.assert_eq(active_tab and active_tab.category_display_id, 2, "row 2 task terminal should be K2")
    helpers.assert_truthy(handle_is_open(handle), "<CR> should attach a visible task terminal")
    helpers.assert_eq(vim.api.nvim_get_current_win(), ui_runtime.get_content_winid(), "task terminal should be focused after selection")
    helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K2" }), "tabbar should render the task terminal label")

    local terminal_lines = vim.api.nvim_buf_get_lines(handle.buf, 0, -1, false)
    helpers.assert_truthy(vim.deep_equal(terminal_lines, { "cmd: sh -c echo qck-task" }), "task terminal should run the selected task command")
  end)

  vim.notify = original_notify
  if not ok then
    error(err)
  end
end

function scenarios.task_runner_reorders_workspace_tasks()
  local env = helpers.load_qck()
  local qck, storage, task_runner, workspace =
    env.qck, env.storage, env.task_runner, env.workspace

  storage.set_task_cmd(workspace, "lint", "echo lint")
  storage.set_task_cmd(workspace, "test", "echo test")
  storage.set_task_cmd(workspace, "build", "echo build")

  qck.run_task()
  local runner_win = task_runner.get_winid()
  local runner_buf = vim.api.nvim_win_get_buf(runner_win)

  helpers.assert_truthy(
    vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), {
      "1. lint  │ echo lint",
      "2. test  │ echo test",
      "3. build │ echo build",
    }),
    "task runner should start in stored task order"
  )

  feed("J")
  helpers.assert_truthy(
    vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), {
      "1. test  │ echo test",
      "2. lint  │ echo lint",
      "3. build │ echo build",
    }),
    "J should swap the selected task with the next task"
  )
  helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 2, "J should keep the moved task selected")

  feed("K")
  helpers.assert_truthy(
    vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), {
      "1. lint  │ echo lint",
      "2. test  │ echo test",
      "3. build │ echo build",
    }),
    "K should swap the selected task with the previous task"
  )
  helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 1, "K should keep the moved task selected")

  feed("K")
  helpers.assert_truthy(
    vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), {
      "1. lint  │ echo lint",
      "2. test  │ echo test",
      "3. build │ echo build",
    }),
    "K on the first task should be a no-op"
  )
  helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 1, "K no-op should keep cursor on the first task")

  feed("j")
  feed("j")
  feed("J")
  helpers.assert_truthy(
    vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), {
      "1. lint  │ echo lint",
      "2. test  │ echo test",
      "3. build │ echo build",
    }),
    "J on the last task should be a no-op"
  )
  helpers.assert_eq(vim.api.nvim_win_get_cursor(runner_win)[1], 3, "J no-op should keep cursor on the last task")

  feed("K")
  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(workspace), {
      { name = "lint", cmd = "echo lint", order = 1 },
      { name = "build", cmd = "echo build", order = 2 },
      { name = "test", cmd = "echo test", order = 3 },
    }),
    "task runner reorder should persist the stored task order"
  )

  feed("<Esc>")
  qck.run_task()
  runner_win = task_runner.get_winid()
  runner_buf = vim.api.nvim_win_get_buf(runner_win)
  helpers.assert_truthy(
    vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), {
      "1. lint  │ echo lint",
      "2. build │ echo build",
      "3. test  │ echo test",
    }),
    "reopened task runner should preserve reordered storage order"
  )
end

function scenarios.task_terminal_finish_keeps_task_tab_open()
  local env = helpers.load_qck()
  local qck, storage, task_runner, ui_state, tabbar, workspace =
    env.qck, env.storage, env.task_runner, env.ui_state, env.tabbar, env.workspace
  local mock_snacks = require("mock_snacks")

  storage.set_task_cmd(workspace, "lint", { "sh", "-c", "echo qck-task" })

  qck.run_task()
  feed("<CR>")

  local task_tab_id = ui_state.resolve_active_tab()
  local task_tab = task_tab_id and ui_state.get_tab(task_tab_id) or nil
  local task_handle = task_tab and task_tab.terminal or nil
  helpers.assert_truthy(task_tab_id ~= nil and handle_is_open(task_handle), "task runner should create a visible task terminal")
  helpers.assert_eq(task_tab and task_tab.category_label, "K", "task terminal should use K labels")
  helpers.assert_eq(task_handle.auto_close, false, "task terminal should opt out of command-finish auto-close")

  mock_snacks.finish_handle(task_handle)
  vim.wait(20, function() return false end)

  helpers.assert_truthy(handle_is_open(task_handle), "finished task terminal should stay open for user acknowledgement")
  helpers.assert_truthy(ui_state.get_tab(task_tab_id) ~= nil, "finished task terminal should remain in ui state")
  helpers.assert_eq(ui_state.resolve_active_tab(), task_tab_id, "finished task terminal should remain active")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K1" }), "tabbar should keep the finished task terminal row")
  helpers.assert_eq(task_runner.get_winid(), nil, "task runner should stay closed after task spawn")
end

function scenarios.task_terminal_finish_preserves_mixed_tabbar()
  local env = helpers.load_qck()
  local qck, storage, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui_state, env.tabbar, env.workspace
  local mock_snacks = require("mock_snacks")

  qck.open()
  local base_tab_id = ui_state.resolve_active_tab()
  local base_tab = base_tab_id and ui_state.get_tab(base_tab_id) or nil
  local base_handle = base_tab and base_tab.terminal or nil
  helpers.assert_truthy(base_tab_id ~= nil and handle_is_open(base_handle), "base terminal should start visible")
  helpers.assert_eq(base_tab and base_tab.category_label, "T", "regular terminal should keep T labels")

  storage.set_task_cmd(workspace, "lint", "echo lint")
  qck.run_task()
  feed("<CR>")

  local task_tab_id = ui_state.resolve_active_tab()
  local task_tab = task_tab_id and ui_state.get_tab(task_tab_id) or nil
  local task_handle = task_tab and task_tab.terminal or nil
  helpers.assert_truthy(task_tab_id ~= nil and task_tab_id ~= base_tab_id, "task terminal should create a new tab")
  helpers.assert_eq(task_tab and task_tab.category_label, "K", "task terminal should use K labels in mixed traversal")
  helpers.assert_truthy(handle_is_open(task_handle), "task terminal should be visible before finish")
  helpers.assert_truthy(not handle_is_open(base_handle), "base terminal should be hidden while task terminal is active")
  local tabbar_win = tabbar.get_winid()
  local divider = tabbar_divider_label(tabbar_win)
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar_win), { "K1", divider, "T1" }), "tabbar should render a divider between task and regular terminals")

  mock_snacks.finish_handle(task_handle)
  vim.wait(20, function() return false end)

  helpers.assert_truthy(handle_is_open(task_handle), "finished task terminal should remain visible")
  helpers.assert_truthy(not handle_is_open(base_handle), "base terminal should stay hidden while finished task remains active")
  helpers.assert_eq(ui_state.resolve_active_tab(), task_tab_id, "finished active task should stay active")
  tabbar_win = tabbar.get_winid()
  divider = tabbar_divider_label(tabbar_win)
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar_win), { "K1", divider, "T1" }), "tabbar should keep divider between task and regular terminals after task finish")
end

function scenarios.task_terminals_are_pinned_before_regular_terminals()
  local env = helpers.load_qck()
  local qck, storage, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui_state, env.tabbar, env.workspace

  helpers.assert_truthy(
    vim.deep_equal(ui_state.category_keys(), { "task", "terminal" }),
    "plugin setup should register task category before regular terminal category"
  )

  qck.open()
  local terminal_tab_id = ui_state.resolve_active_tab()

  storage.set_task_cmd(workspace, "lint", "echo lint")
  qck.run_task()
  feed("<CR>")

  local task_tab_id = ui_state.resolve_active_tab()
  helpers.assert_truthy(task_tab_id ~= nil and task_tab_id ~= terminal_tab_id, "task runner should create a separate task tab")
  helpers.assert_truthy(
    vim.deep_equal(ui_state.traversal_ids(), { task_tab_id, terminal_tab_id }),
    "ui traversal should pin task terminals before regular terminals"
  )
  local tabbar_win = tabbar.get_winid()
  helpers.assert_truthy(
    vim.deep_equal(tabbar_labels(tabbar_win), { "K1", tabbar_divider_label(tabbar_win), "T1" }),
    "tabbar should render a divider between pinned task and regular terminals"
  )
end

function scenarios.tabbar_skips_kind_divider()
  local env = helpers.load_qck()
  local qck, storage, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui_state, env.tabbar, env.workspace

  qck.open()
  local terminal_tab_id = ui_state.resolve_active_tab()
  storage.set_task_cmd(workspace, "lint", "echo lint")
  qck.run_task()
  feed("<CR>")
  local task_tab_id = ui_state.resolve_active_tab()
  local tabbar_win = tabbar.get_winid()

  helpers.assert_truthy(type(tabbar_win) == "number", "mixed tabbar scenario should show tabbar")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar_win), { "K1", tabbar_divider_label(tabbar_win), "T1" }), "tabbar should render a divider row")

  qck.switch_focus()
  helpers.assert_eq(vim.api.nvim_get_current_win(), tabbar_win, "switch_focus() should focus tabbar for divider navigation")
  helpers.assert_eq(vim.api.nvim_win_get_cursor(tabbar_win)[1], 1, "tabbar cursor should start on active K row")

  feed("j")
  helpers.assert_eq(vim.api.nvim_win_get_cursor(tabbar_win)[1], 3, "j should skip divider and land on T row")
  feed("k")
  helpers.assert_eq(vim.api.nvim_win_get_cursor(tabbar_win)[1], 1, "k should skip divider and land on K row")
  feed("k")
  helpers.assert_eq(vim.api.nvim_win_get_cursor(tabbar_win)[1], 3, "wrapped k should skip divider")

  vim.api.nvim_win_set_cursor(tabbar_win, { 2, 0 })
  local active_before = ui_state.resolve_active_tab()
  local focused_before = vim.api.nvim_get_current_win()
  feed("<CR>")
  helpers.assert_eq(ui_state.resolve_active_tab(), active_before, "tabbar <CR> on divider should not change active tab")
  helpers.assert_eq(vim.api.nvim_get_current_win(), focused_before, "tabbar <CR> on divider should not change focus")

  local content_before = require("qck.ui.runtime").get_content_winid()
  local mode_before = vim.api.nvim_get_mode().mode
  local clicked = tabbar.handle_left_click({
    winid = tabbar_win,
    line = 2,
    screenrow = vim.fn.screenpos(tabbar_win, 2, 1).row,
  })
  helpers.assert_eq(clicked, false, "mouse click on divider should be ignored")
  helpers.assert_eq(ui_state.resolve_active_tab(), active_before, "mouse click on divider should not change active tab")
  helpers.assert_eq(require("qck.ui.runtime").get_content_winid(), content_before, "mouse click on divider should not change visible content")
  helpers.assert_eq(vim.api.nvim_get_current_win(), focused_before, "mouse click on divider should not change focus")
  helpers.assert_eq(vim.api.nvim_get_mode().mode, mode_before, "mouse click on divider should not change mode")

  helpers.assert_truthy(task_tab_id ~= nil and terminal_tab_id ~= nil, "mixed divider scenario should create both tab kinds")
end

function scenarios.task_runner_reuses_existing_task_terminal()
  local env = helpers.load_qck()
  local qck, storage, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui_state, env.tabbar, env.workspace
  local mock_snacks = require("mock_snacks")

  storage.set_task_cmd(workspace, "lint", "echo lint")

  qck.run_task()
  feed("<CR>")
  local first_task_tab_id = ui_state.resolve_active_tab()
  local first_task_tab = first_task_tab_id and ui_state.get_tab(first_task_tab_id) or nil
  local first_task_handle = first_task_tab and first_task_tab.terminal or nil
  helpers.assert_truthy(first_task_tab_id ~= nil and handle_is_open(first_task_handle), "first task selection should spawn K1")
  helpers.assert_eq(#mock_snacks.get_handles(), 1, "first task selection should create one terminal handle")

  qck.run_task()
  feed("<CR>")
  local reused_task_tab_id = ui_state.resolve_active_tab()
  local reused_task_tab = reused_task_tab_id and ui_state.get_tab(reused_task_tab_id) or nil
  local reused_task_handle = reused_task_tab and reused_task_tab.terminal or nil

  helpers.assert_eq(reused_task_tab_id, first_task_tab_id, "selecting the same command should reuse the existing task tab")
  helpers.assert_eq(reused_task_handle, first_task_handle, "selecting the same command should reuse the existing task handle")
  helpers.assert_eq(#mock_snacks.get_handles(), 1, "selecting the same command should not create another terminal handle")
  helpers.assert_truthy(handle_is_open(first_task_handle), "reused task terminal should stay visible")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K1" }), "reused task terminal should keep one tabbar row")
end

function scenarios.task_runner_reopens_hidden_matching_task_terminal()
  local env = helpers.load_qck()
  local qck, storage, ui, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui, env.ui_state, env.tabbar, env.workspace
  local mock_snacks = require("mock_snacks")

  storage.set_task_cmd(workspace, "lint", "echo lint")

  qck.open()
  local terminal_tab_id = ui_state.resolve_active_tab()
  local terminal_tab = terminal_tab_id and ui_state.get_tab(terminal_tab_id) or nil
  local terminal_handle = terminal_tab and terminal_tab.terminal or nil
  helpers.assert_truthy(terminal_tab_id ~= nil and handle_is_open(terminal_handle), "open() should create a regular terminal")

  qck.run_task()
  feed("<CR>")
  local task_tab_id = ui_state.resolve_active_tab()
  local task_tab = task_tab_id and ui_state.get_tab(task_tab_id) or nil
  local task_handle = task_tab and task_tab.terminal or nil
  helpers.assert_truthy(task_tab_id ~= nil and task_tab_id ~= terminal_tab_id, "task selection should spawn K1")
  helpers.assert_truthy(handle_is_open(task_handle), "task terminal should be visible before hiding it")
  helpers.assert_truthy(not handle_is_open(terminal_handle), "regular terminal should be hidden while task terminal is active")

  helpers.assert_truthy(select(1, ui.set_active_tab(terminal_tab_id)), "test setup should switch back to the regular terminal")
  helpers.assert_truthy(handle_is_open(terminal_handle), "regular terminal should be visible before reuse")
  helpers.assert_truthy(not handle_is_open(task_handle), "task terminal should be hidden while regular terminal is active")

  qck.run_task()
  feed("<CR>")

  helpers.assert_eq(ui_state.resolve_active_tab(), task_tab_id, "selecting a hidden matching task should reselect that task tab")
  helpers.assert_eq(#mock_snacks.get_handles(), 2, "reusing hidden task should not create another terminal handle")
  helpers.assert_truthy(handle_is_open(task_handle), "reused hidden task should be shown again")
  helpers.assert_truthy(not handle_is_open(terminal_handle), "regular terminal should be hidden after task reuse")
  local tabbar_win = tabbar.get_winid()
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar_win), { "K1", tabbar_divider_label(tabbar_win), "T1" }), "tabbar should keep divider between pinned task and terminal rows")
end

function scenarios.task_runner_spawns_distinct_task_terminals_for_distinct_commands()
  local env = helpers.load_qck()
  local qck, storage, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui_state, env.tabbar, env.workspace
  local mock_snacks = require("mock_snacks")

  storage.set_task_cmd(workspace, "lint", "echo lint")
  storage.set_task_cmd(workspace, "test", { "sh", "-c", "echo qck-task" })

  qck.run_task()
  feed("<CR>")
  local lint_tab_id = ui_state.resolve_active_tab()

  qck.run_task()
  feed("j")
  feed("<CR>")
  local test_tab_id = ui_state.resolve_active_tab()

  helpers.assert_truthy(lint_tab_id ~= nil and test_tab_id ~= nil and test_tab_id ~= lint_tab_id, "different commands should create different task tabs")
  helpers.assert_eq(#mock_snacks.get_handles(), 2, "different commands should create separate terminal handles")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K1", "K2" }), "distinct task commands should render separate task rows")
end

function scenarios.task_runner_uses_task_order_for_k_labels()
  local env = helpers.load_qck()
  local qck, storage, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui_state, env.tabbar, env.workspace
  local mock_snacks = require("mock_snacks")

  storage.set_task_cmd(workspace, "lint", "echo shared")
  storage.set_task_cmd(workspace, "test", "echo shared")

  qck.run_task()
  feed("j")
  feed("<CR>")
  local test_tab_id = ui_state.resolve_active_tab()
  local test_tab = test_tab_id and ui_state.get_tab(test_tab_id) or nil
  helpers.assert_truthy(test_tab_id ~= nil and handle_is_open(test_tab and test_tab.terminal), "selecting row 2 should spawn a task terminal")
  helpers.assert_eq(test_tab and test_tab.category_display_id, 2, "row 2 task should use K2 even when it is the first spawned task")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K2" }), "tabbar should render the task order label")

  qck.run_task()
  feed("k")
  feed("<CR>")
  local lint_tab_id = ui_state.resolve_active_tab()
  local lint_tab = lint_tab_id and ui_state.get_tab(lint_tab_id) or nil

  helpers.assert_truthy(lint_tab_id ~= nil and lint_tab_id ~= test_tab_id, "same-command tasks should create distinct task tabs")
  helpers.assert_eq(lint_tab and lint_tab.category_display_id, 1, "row 1 task should use K1")
  helpers.assert_eq(#mock_snacks.get_handles(), 2, "same-command tasks should not reuse by command")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K2", "K1" }), "task labels should come from task order, not spawn order")
end

function scenarios.task_runner_updates_k_labels_after_reorder()
  local env = helpers.load_qck()
  local qck, storage, ui_state, tabbar, workspace =
    env.qck, env.storage, env.ui_state, env.tabbar, env.workspace
  local mock_snacks = require("mock_snacks")

  storage.set_task_cmd(workspace, "lint", "echo lint")
  storage.set_task_cmd(workspace, "test", "echo test")

  qck.run_task()
  feed("<CR>")
  local lint_tab_id = ui_state.resolve_active_tab()
  local lint_tab = lint_tab_id and ui_state.get_tab(lint_tab_id) or nil
  local lint_handle = lint_tab and lint_tab.terminal or nil

  qck.run_task()
  feed("j")
  feed("<CR>")
  local test_tab_id = ui_state.resolve_active_tab()
  local test_tab = test_tab_id and ui_state.get_tab(test_tab_id) or nil
  local test_handle = test_tab and test_tab.terminal or nil

  helpers.assert_truthy(lint_tab_id ~= nil and test_tab_id ~= nil and lint_tab_id ~= test_tab_id, "test setup should create two task tabs")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K1", "K2" }), "task labels should start in storage order")

  qck.run_task()
  feed("j")
  feed("K")

  helpers.assert_eq(#mock_snacks.get_handles(), 2, "reordering tasks should not create or close task terminals")
  helpers.assert_eq(ui_state.get_tab(lint_tab_id).category_display_id, 2, "live lint tab should relabel to its new task order")
  helpers.assert_eq(ui_state.get_tab(test_tab_id).category_display_id, 1, "live test tab should relabel to its new task order")
  helpers.assert_eq(ui_state.get_tab(lint_tab_id).terminal, lint_handle, "lint terminal handle should be preserved across relabel")
  helpers.assert_eq(ui_state.get_tab(test_tab_id).terminal, test_handle, "test terminal handle should be preserved across relabel")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(tabbar.get_winid()), { "K2", "K1" }), "visible tabbar should rerender updated task labels")
end

function scenarios.task_runner_edits_selected_task()
  local env = helpers.load_qck()
  local qck, storage, task_form, task_runner, workspace =
    env.qck, env.storage, env.task_form, env.task_runner, env.workspace

  storage.set_task_cmd(workspace, "lint", "echo lint")
  storage.set_task_cmd(workspace, "test", "echo test")

  qck.run_task()
  feed("j")
  feed("e")

  helpers.assert_eq(task_runner.get_winid(), nil, "e should close the task runner")
  local form_win = task_form.get_winid()
  helpers.assert_truthy(type(form_win) == "number", "e should open the task edit form")
  helpers.assert_eq(window_title(form_win), "QCK Edit Task", "runner edit should use edit form title")

  local form_buf = vim.api.nvim_win_get_buf(form_win)
  helpers.assert_form_scaffold(form_buf, "Please edit the name and command of the task")
  local lines = vim.api.nvim_buf_get_lines(form_buf, 0, -1, false)
  helpers.assert_eq(lines[3], "Name    | test", "runner edit should prefill selected task name")
  helpers.assert_eq(lines[4], "Command | echo test", "runner edit should prefill selected task command")
end

function scenarios.task_runner_edit_empty_workspace_noops()
  local env = helpers.load_qck()
  local qck, task_form, task_runner = env.qck, env.task_form, env.task_runner

  qck.run_task()
  local runner_win = task_runner.get_winid()
  helpers.assert_truthy(type(runner_win) == "number", "run_task() should open task runner for empty workspace")

  feed("e")
  helpers.assert_eq(task_runner.get_winid(), runner_win, "e should keep empty task runner open")
  helpers.assert_eq(task_form.get_winid(), nil, "e should not open edit form for empty workspace")
end

function scenarios.task_runner_empty_workspace()
  local env = helpers.load_qck()
  local qck, task_runner = env.qck, env.task_runner
  local notifications = {}
  local original_notify = vim.notify

  vim.notify = function(msg, level)
    notifications[#notifications + 1] = { msg = msg, level = level }
  end

  local ok, err = pcall(function()
    qck.run_task()
    local runner_win = task_runner.get_winid()
    helpers.assert_truthy(type(runner_win) == "number", "run_task() should open empty task runner window")

    local runner_buf = vim.api.nvim_win_get_buf(runner_win)
    local lines = vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false)
    helpers.assert_truthy(vim.deep_equal(lines, { "No tasks for current workspace" }), "empty task runner should render empty state")

    feed("<CR>")
    helpers.assert_eq(#notifications, 0, "<CR> should be a no-op without runnable tasks")

    feed("<Esc>")
    helpers.assert_eq(task_runner.get_winid(), nil, "<Esc> should close empty task runner")
  end)

  vim.notify = original_notify
  if not ok then
    error(err)
  end
end

function scenarios.storage_roundtrip()
  local env = helpers.load_qck()
  local storage = env.storage
  local workspace = env.workspace
  local other_workspace = workspace .. "-other"

  storage.set_task_cmd(workspace, "lint", { "echo", "lint" })
  storage.set_task_cmd(other_workspace, "test", "echo test")

  local ok_save = storage.save()
  helpers.assert_truthy(ok_save, "storage save should persist workspace tasks")

  storage.workspaces = {}
  local ok_load = storage.load()
  helpers.assert_truthy(ok_load, "storage load should restore saved workspace tasks")

  assert_cmd(
    storage.get_task_cmd(workspace, "lint"),
    { "echo", "lint" },
    "storage should round-trip list commands for the current workspace"
  )
  helpers.assert_eq(
    storage.get_task_cmd(other_workspace, "test"),
    "echo test",
    "storage should keep other workspace task commands separate"
  )
  assert_cmd(
    storage.get_workspace_tasks(workspace),
    { lint = { "echo", "lint" } },
    "storage should expose normalized workspace task definitions"
  )

  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(workspace), {
      { name = "lint", cmd = { "echo", "lint" }, order = 1 },
    }),
    "storage should expose ordered task entries"
  )
end

function scenarios.storage_task_ordering()
  local env = helpers.load_qck()
  local qck, storage, task_form, task_runner, workspace =
    env.qck, env.storage, env.task_form, env.task_runner, env.workspace

  storage.set_task_cmd(workspace, "zeta", "echo zeta")
  storage.set_task_cmd(workspace, "alpha", "echo alpha")
  storage.set_task_cmd(workspace, "zeta", "echo zeta edited")

  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(workspace), {
      { name = "zeta", cmd = "echo zeta edited", order = 1 },
      { name = "alpha", cmd = "echo alpha", order = 2 },
    }),
    "storage should keep creation order when updating an existing task"
  )

  qck.run_task()
  local runner_win = task_runner.get_winid()
  local runner_buf = vim.api.nvim_win_get_buf(runner_win)
  helpers.assert_truthy(
    vim.deep_equal(vim.api.nvim_buf_get_lines(runner_buf, 0, -1, false), {
      "1. zeta  │ echo zeta edited",
      "2. alpha │ echo alpha",
    }),
    "task runner should render tasks in creation order instead of alphabetical order"
  )
  feed("<Esc>")

  task_form.open_edit("zeta", "echo zeta edited")
  local form_buf = vim.api.nvim_win_get_buf(task_form.get_winid())
  helpers.set_form_fields(form_buf, "Name: beta", "Command: echo beta")
  task_form.submit()

  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(workspace), {
      { name = "beta", cmd = "echo beta", order = 1 },
      { name = "alpha", cmd = "echo alpha", order = 2 },
    }),
    "renaming a task should preserve its stored order"
  )

  helpers.write_storage({
    version = "0.1.0",
    workspaces = {
      [workspace] = {
        tasks = {
          zeta = { cmd = "echo zeta" },
          alpha = { cmd = "echo alpha" },
        },
      },
    },
  })

  local ok_load = storage.load()
  helpers.assert_truthy(ok_load, "storage load should backfill task order for old task entries")
  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(workspace), {
      { name = "alpha", cmd = "echo alpha", order = 1 },
      { name = "zeta", cmd = "echo zeta", order = 2 },
    }),
    "old task entries should receive deterministic order numbers by task name"
  )
end

function scenarios.storage_task_order_moves()
  local env = helpers.load_qck()
  local storage, workspace = env.storage, env.workspace
  local other_workspace = workspace .. "-other"

  storage.set_task_cmd(workspace, "lint", "echo lint")
  storage.set_task_cmd(workspace, "test", "echo test")
  storage.set_task_cmd(workspace, "build", "echo build")
  storage.set_task_cmd(other_workspace, "other", "echo other")

  helpers.assert_eq(storage.move_task_order(workspace, "missing", 1), false, "moving a missing task should fail")
  helpers.assert_eq(storage.move_task_order(workspace, "lint", -1), false, "moving the first task up should fail")

  local ok_down, err_down = storage.move_task_order(workspace, "lint", 1)
  helpers.assert_truthy(ok_down, "moving a task down should succeed: " .. tostring(err_down))
  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(workspace), {
      { name = "test", cmd = "echo test", order = 1 },
      { name = "lint", cmd = "echo lint", order = 2 },
      { name = "build", cmd = "echo build", order = 3 },
    }),
    "moving a task down should swap adjacent order numbers and preserve commands"
  )

  local ok_up, err_up = storage.move_task_order(workspace, "lint", -1)
  helpers.assert_truthy(ok_up, "moving a task up should succeed: " .. tostring(err_up))
  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(workspace), {
      { name = "lint", cmd = "echo lint", order = 1 },
      { name = "test", cmd = "echo test", order = 2 },
      { name = "build", cmd = "echo build", order = 3 },
    }),
    "moving a task up should swap adjacent order numbers and preserve commands"
  )

  helpers.assert_truthy(
    vim.deep_equal(storage.get_workspace_task_entries(other_workspace), {
      { name = "other", cmd = "echo other", order = 1 },
    }),
    "moving a task should not affect another workspace"
  )
end

function scenarios.storage_persists_across_module_reload()
  local env = helpers.load_qck()
  local storage = env.storage
  local workspace = env.workspace

  storage.set_task_cmd(workspace, "lint", "echo lint")
  local ok_save = storage.save()
  helpers.assert_truthy(ok_save, "storage save should persist task before module reload")

  local loaded_names = {}
  for name in pairs(package.loaded) do
    if name == "qck" or name:match("^qck%.") then
      loaded_names[#loaded_names + 1] = name
    end
  end
  for _, name in ipairs(loaded_names) do
    package.loaded[name] = nil
  end

  local reloaded_storage = require("qck.tasks.storage")
  local ok_load = reloaded_storage.load()
  helpers.assert_truthy(ok_load, "storage load should succeed after module reload")
  helpers.assert_eq(reloaded_storage.get_task_cmd(workspace, "lint"), "echo lint", "storage should preserve tasks across module reload")
end

function scenarios.storage_save_creates_missing_data_dir()
  local env = helpers.load_qck()
  local storage = env.storage
  local workspace = env.workspace
  local data_dir = vim.fn.stdpath("data")
  local storage_path = data_dir .. "/qck.json"

  vim.fn.delete(data_dir, "rf")
  storage.ok = true
  storage.workspaces = vim.empty_dict()
  storage.set_task_cmd(workspace, "lint", "echo lint")

  local ok_save, save_err = storage.save()
  helpers.assert_truthy(ok_save, "storage save should create missing data directory: " .. tostring(save_err))
  helpers.assert_eq(vim.fn.filereadable(storage_path), 1, "storage save should create qck.json")

  storage.workspaces = {}
  local ok_load = storage.load()
  helpers.assert_truthy(ok_load, "storage load should read file created after missing data dir")
  helpers.assert_eq(storage.get_task_cmd(workspace, "lint"), "echo lint", "storage should preserve task after creating missing data dir")
end

function scenarios.storage_empty_state_writes_object_maps()
  local env = helpers.load_qck()
  local qck, storage, workspace = env.qck, env.storage, env.workspace
  local storage_path = vim.fn.stdpath("data") .. "/qck.json"

  storage.set_task_cmd(workspace, "lint", "echo lint")
  helpers.assert_truthy(storage.save(), "storage should save seeded task")

  qck.clear_storage()
  local encoded = table.concat(vim.fn.readfile(storage_path), "\n")
  local decoded = vim.json.decode(encoded)

  helpers.assert_truthy(type(decoded.workspaces) == "table", "storage workspaces should decode to a table")
  helpers.assert_truthy(encoded:find('"workspaces":{}', 1, true) ~= nil, "empty storage workspaces should be encoded as a JSON object")
end

function scenarios.ui_state_registration_and_traversal()
  local state = require("qck.ui.state")
  state.reset()

  local ok_terminal = state.register_category({ key = "terminal", label = "T" })
  helpers.assert_truthy(ok_terminal, "ui state should register a terminal category")
  local ok_terminal_repeat = state.register_category({ key = "terminal", label = "T" })
  helpers.assert_truthy(ok_terminal_repeat, "ui state should allow idempotent category registration")

  local ok_task = state.register_category({ key = "task", label = "K" })
  helpers.assert_truthy(ok_task, "ui state should register a second category")
  helpers.assert_truthy(
    vim.deep_equal(state.category_keys(), { "terminal", "task" }),
    "ui state should preserve category registration order"
  )

  local ok_conflict = state.register_category({ key = "terminal", label = "X" })
  helpers.assert_truthy(ok_conflict, "ui state should allow conflicting re-registration before category use")
  helpers.assert_eq(state.get_category("terminal").label, "X", "ui state should update unused category metadata on re-registration")
  local ok_duplicate_label = state.register_category({ key = "notes", label = "K" })
  helpers.assert_eq(ok_duplicate_label, false, "ui state should reject duplicate category labels")

  local terminal_a = {}
  local terminal_b = {}
  local task_a = {}
  local task_b = {}
  local terminal_c = {}

  local first_terminal_id = select(1, state.register_tab("terminal", terminal_a))
  local second_terminal_id = select(1, state.register_tab("terminal", terminal_b))
  local first_task_id = select(1, state.register_tab("task", task_a))

  helpers.assert_eq(first_terminal_id, 1, "ui state should assign stable tab ids from 1")
  helpers.assert_eq(second_terminal_id, 2, "ui state should increment tab ids without reuse")
  helpers.assert_eq(first_task_id, 3, "ui state should keep one global tab id sequence")

  local first_terminal = state.get_tab(first_terminal_id)
  local second_terminal = state.get_tab(second_terminal_id)
  local first_task = state.get_tab(first_task_id)

  helpers.assert_eq(first_terminal.category_key, "terminal", "registered terminal should keep category key metadata")
  helpers.assert_eq(first_terminal.category_label, "X", "registered terminal should derive the latest unused category label metadata")
  helpers.assert_eq(first_terminal.category_display_id, 1, "first terminal should use the first category display id")
  helpers.assert_eq(second_terminal.category_display_id, 2, "second terminal should increment the category display id")
  helpers.assert_eq(first_task.category_display_id, 1, "display ids should be scoped per category")
  local second_task_id = select(1, state.register_tab("task", task_b, { display_id = 7 }))
  helpers.assert_eq(state.get_tab(second_task_id).category_display_id, 7, "ui state should accept explicit display ids")
  helpers.assert_eq(
    select(1, state.set_tab_display_id(second_task_id, 4)),
    true,
    "ui state should update live tab display ids"
  )
  helpers.assert_eq(state.get_tab(second_task_id).category_display_id, 4, "ui state should expose updated display ids")
  helpers.assert_eq(
    select(1, state.set_tab_display_id(second_task_id, 0)),
    false,
    "ui state should reject invalid display ids"
  )
  helpers.assert_truthy(
    state.get_tab_by_terminal(terminal_a).id == first_terminal_id,
    "ui state should index tabs by their registered terminal handle"
  )
  helpers.assert_truthy(
    state.register_category({ key = "terminal", label = "X" }),
    "ui state should allow idempotent re-registration after category use"
  )
  helpers.assert_eq(
    select(1, state.register_category({ key = "terminal", label = "Y" })),
    false,
    "ui state should reject conflicting re-registration once the category is in use"
  )
  helpers.assert_eq(select(1, state.register_tab("terminal", terminal_a)), nil, "ui state should reject duplicate terminal registration")

  helpers.assert_truthy(
    vim.deep_equal(state.category_tab_ids("terminal"), { first_terminal_id, second_terminal_id }),
    "ui state should keep per-category ordering"
  )
  helpers.assert_truthy(
    vim.deep_equal(state.traversal_ids(), { first_terminal_id, second_terminal_id, first_task_id, second_task_id }),
    "ui state should derive global traversal from category order and per-category order"
  )

  local moved_up = state.move_tab(second_terminal_id, -1)
  helpers.assert_truthy(moved_up, "ui state should allow adjacent category-local movement")
  helpers.assert_truthy(
    vim.deep_equal(state.category_tab_ids("terminal"), { second_terminal_id, first_terminal_id }),
    "ui state should update category-local order after movement"
  )
  helpers.assert_truthy(
    vim.deep_equal(state.traversal_ids(), { second_terminal_id, first_terminal_id, first_task_id, second_task_id }),
    "ui state traversal should follow category-local movement"
  )
  helpers.assert_eq(state.move_tab(second_terminal_id, -1), false, "ui state should no-op at a category boundary")

  local deleted = state.delete_tab(first_terminal_id)
  helpers.assert_truthy(deleted, "ui state should delete registered tabs")
  helpers.assert_eq(state.get_tab(first_terminal_id), nil, "ui state should remove deleted tabs from the registry")
  helpers.assert_eq(
    state.resolve_active_tab(),
    first_task_id,
    "ui state should adopt the next live tab in global traversal order when deleting the active tab"
  )
  helpers.assert_eq(
    state.get_tab(second_terminal_id).category_display_id,
    2,
    "ui state should keep survivor display ids stable after delete"
  )

  local reused_terminal_id = select(1, state.register_tab("terminal", terminal_c))
  helpers.assert_eq(reused_terminal_id, 5, "ui state should not reuse deleted tab ids")
  helpers.assert_eq(
    state.get_tab(reused_terminal_id).category_display_id,
    1,
    "ui state should reuse the lowest missing category display id after delete"
  )
  helpers.assert_truthy(
    vim.deep_equal(state.category_tab_ids("terminal"), { second_terminal_id, reused_terminal_id }),
    "ui state should append new tabs within their category order"
  )
  helpers.assert_truthy(
    vim.deep_equal(state.traversal_ids(), { second_terminal_id, reused_terminal_id, first_task_id, second_task_id }),
    "ui state should preserve global traversal after display-id reuse"
  )
  helpers.assert_truthy(state.set_active_tab(first_task_id), "ui state should allow selecting the last traversal tab")
  helpers.assert_truthy(state.delete_tab(first_task_id), "ui state should delete the selected trailing traversal tab")
  helpers.assert_truthy(state.delete_tab(second_task_id), "ui state should delete explicit display-id tabs")
  helpers.assert_eq(
    state.resolve_active_tab(),
    reused_terminal_id,
    "ui state should fall back to the previous live tab when deleting the last traversal tab"
  )

  state.set_active_tab_id(nil)
  helpers.assert_eq(
    state.resolve_active_tab(),
    second_terminal_id,
    "ui state should fall back to the first live tab when no active tab is stored"
  )
  state.set_active_tab_id(999)
  helpers.assert_eq(
    state.resolve_active_tab(),
    second_terminal_id,
    "ui state should fall back to the first live tab when the active tab is stale"
  )
end

function scenarios.ui_runtime_and_layout_scaffolding()
  local runtime = require("qck.ui.runtime")
  local ui_layout = require("qck.ui.layout")

  runtime.reset()

  local content_buf = vim.api.nvim_create_buf(false, true)
  local content_win = vim.api.nvim_open_win(content_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 10,
    height = 4,
    style = "minimal",
  })
  local tabbar_buf = vim.api.nvim_create_buf(false, true)
  local tabbar_win = vim.api.nvim_open_win(tabbar_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 6,
    height = 4,
    style = "minimal",
  })

  runtime.set_content_winid(content_win)
  runtime.set_tabbar_bufnr(tabbar_buf)
  runtime.set_tabbar_winid(tabbar_win)
  helpers.assert_eq(runtime.get_content_winid(), content_win, "ui runtime should track the visible content winid")
  helpers.assert_eq(runtime.get_tabbar_bufnr(), tabbar_buf, "ui runtime should track the tabbar bufnr")
  helpers.assert_eq(runtime.get_tabbar_winid(), tabbar_win, "ui runtime should track the tabbar winid")
  helpers.assert_truthy(runtime.is_visible(), "ui runtime should report visibility when content is open")

  local handle_a = {}
  local handle_b = {}
  helpers.assert_truthy(select(1, runtime.register_handle(1, handle_a)), "ui runtime should register owned handles")
  helpers.assert_eq(runtime.get_handle_owner(handle_a), 1, "ui runtime should reverse-index registered handles")
  helpers.assert_eq(select(1, runtime.register_handle(2, handle_a)), false, "ui runtime should reject duplicate handle ownership")
  helpers.assert_eq(select(1, runtime.register_handle(1, handle_b)), false, "ui runtime should reject conflicting owner re-registration")
  runtime.unregister_handle(1)
  helpers.assert_eq(runtime.get_handle_owner(handle_a), nil, "ui runtime should unregister owned handles")

  runtime.set_owner_watchers(7, { watched_term_win = 11, terminal_watch_autocmd_id = 12 })
  local owner_watchers = runtime.get_owner_watchers(7)
  helpers.assert_eq(owner_watchers.watched_term_win, 11, "ui runtime should store per-owner watcher bookkeeping")
  owner_watchers.watched_term_win = 99
  helpers.assert_eq(runtime.get_owner_watchers(7).watched_term_win, 11, "ui runtime should return watcher bookkeeping by copy")

  runtime.set_global_watchers({ focus_leave = 21, resize = 22 })
  local global_watchers = runtime.get_global_watchers()
  helpers.assert_eq(global_watchers.focus_leave, 21, "ui runtime should store global watcher bookkeeping")
  global_watchers.focus_leave = 99
  helpers.assert_eq(runtime.get_global_watchers().focus_leave, 21, "ui runtime should copy global watcher bookkeeping")

  local shared = ui_layout.build_shared_float_configs(content_win)
  local expected = helpers.expected_layout(ui_layout)
  helpers.assert_truthy(shared ~= nil, "ui layout should build shared float configs for a valid content window")
  helpers.assert_eq(shared.tabbar.width, expected.tabbar_width, "ui layout should preserve tabbar width math")
  helpers.assert_eq(
    math.floor(tonumber(shared.terminal.col) or 0),
    expected.horizontal_margin + expected.tabbar_width + expected.gap_width,
    "ui layout should preserve content offset math"
  )
  helpers.assert_eq(shared.terminal.height, expected.total_height, "ui layout should preserve shared height math")

  vim.api.nvim_win_close(tabbar_win, true)
  helpers.assert_eq(runtime.get_tabbar_winid(), nil, "ui runtime should clear stale tabbar winids on read")
  helpers.assert_eq(runtime.get_tabbar_bufnr(), tabbar_buf, "ui runtime should keep a valid tabbar buffer across win closes")

  vim.api.nvim_win_close(content_win, true)
  helpers.assert_eq(runtime.get_content_winid(), nil, "ui runtime should clear stale content winids on read")
  helpers.assert_eq(runtime.is_visible(), false, "ui runtime should report hidden when content closes")
end

function scenarios.ui_tabbar_renders_from_ui_state()
  local ui_state = require("qck.ui.state")
  local ui_runtime = require("qck.ui.runtime")
  local ui_tabbar = require("qck.ui.tabbar")

  ui_state.reset()
  ui_runtime.reset()

  helpers.assert_truthy(
    ui_state.register_category({ key = "terminal", label = "T" }),
    "ui tabbar test should register the terminal category"
  )

  local terminal_a = {}
  local terminal_b = {}
  local first_tab_id = select(1, ui_state.register_tab("terminal", terminal_a))
  local second_tab_id = select(1, ui_state.register_tab("terminal", terminal_b))
  helpers.assert_truthy(first_tab_id ~= nil and second_tab_id ~= nil, "ui tabbar test should register tabs")
  helpers.assert_truthy(ui_state.move_tab(second_tab_id, -1), "ui tabbar test should reorder tabs through ui state")
  helpers.assert_truthy(ui_state.set_active_tab(first_tab_id), "ui tabbar test should set the active tab")

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 8,
    height = 4,
    style = "minimal",
  })
  ui_runtime.set_tabbar_bufnr(buf)
  ui_runtime.set_tabbar_winid(win)

  ui_tabbar.render()

  helpers.assert_truthy(vim.deep_equal(tabbar_labels(win), { "T2", "T1" }), "ui tabbar should render labels from ui state traversal order")

  local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
  helpers.assert_eq(#marks, 1, "ui tabbar should keep one active-row highlight mark")
  helpers.assert_eq(marks[1][2], 1, "ui tabbar should highlight the active ui-state row")

  ui_tabbar.hide()
  ui_state.reset()
  ui_runtime.reset()
end

function scenarios.ui_init_orchestration_contract()
  require("mock_snacks").install()

  local ui = require("qck.ui")
  local ui_state = require("qck.ui.state")
  local ui_runtime = require("qck.ui.runtime")
  local ui_tabbar = require("qck.ui.tabbar")
  local snacks = require("snacks")

  ui_tabbar.hide()
  ui_state.reset()
  ui_runtime.reset()
  ui.setup()

  local global_watchers = ui_runtime.get_global_watchers()
  helpers.assert_truthy(type(global_watchers.focus_leave_autocmd_id) == "number", "ui setup should install the global focus-leave watcher")
  helpers.assert_truthy(type(global_watchers.resize_autocmd_id) == "number", "ui setup should install the global resize watcher")

  helpers.assert_truthy(ui.register_category({ key = "terminal", label = "T" }), "ui init should register categories")

  local handle_a = snacks.terminal.open(nil, { count = 1 })
  local first_tab_id = select(1, ui.attach_and_show("terminal", handle_a))
  helpers.assert_truthy(first_tab_id ~= nil, "attach_and_show() should register and show the first tab")
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "attach_and_show() should make the new tab active")
  helpers.assert_eq(ui_runtime.get_content_winid(), handle_a.win, "attach_and_show() should track the visible content winid")
  helpers.assert_truthy(type(ui_tabbar.get_winid()) == "number", "attach_and_show() should show the tabbar")
  local first_watchers = ui_runtime.get_owner_watchers(first_tab_id)
  helpers.assert_truthy(type(first_watchers.buf_wipeout_autocmd_id) == "number", "attach_and_show() should install the per-tab invalidation watcher")
  helpers.assert_truthy(type(first_watchers.content_close_autocmd_id) == "number", "attach_and_show() should install the visible content close watcher")
  helpers.assert_truthy(type(first_watchers.tabbar_close_autocmd_id) == "number", "attach_and_show() should install the tabbar close watcher")

  local handle_b = snacks.terminal.open(nil, { count = 2 })
  local second_tab_id = select(1, ui.attach_and_show("terminal", handle_b))
  helpers.assert_truthy(second_tab_id ~= nil, "attach_and_show() should register and show the second tab")
  helpers.assert_truthy(not handle_a:valid(), "showing a new tab should hide the previous ui-owned tab window")
  helpers.assert_truthy(handle_b:valid(), "showing a new tab should keep the new tab visible")
  local first_hidden_watchers = ui_runtime.get_owner_watchers(first_tab_id)
  helpers.assert_truthy(type(first_hidden_watchers.buf_wipeout_autocmd_id) == "number", "showing a new tab should preserve the previous tab's invalidation watcher")
  helpers.assert_eq(first_hidden_watchers.content_close_autocmd_id, nil, "showing a new tab should clear the previous tab's visible close watcher")
  helpers.assert_eq(first_hidden_watchers.tabbar_close_autocmd_id, nil, "showing a new tab should clear the previous tab's tabbar close watcher")

  ui.hide()
  helpers.assert_truthy(not handle_b:valid(), "hide() should hide the active tab without deleting it")
  helpers.assert_eq(ui_tabbar.get_winid(), nil, "hide() should close the tabbar")
  helpers.assert_eq(ui_state.resolve_active_tab(), second_tab_id, "hide() should keep the active tab selected")
  local hidden_watchers = ui_runtime.get_owner_watchers(second_tab_id)
  helpers.assert_truthy(type(hidden_watchers.buf_wipeout_autocmd_id) == "number", "hide() should preserve the per-tab invalidation watcher")
  helpers.assert_eq(hidden_watchers.content_close_autocmd_id, nil, "hide() should clear the visible content close watcher")
  helpers.assert_eq(hidden_watchers.tabbar_close_autocmd_id, nil, "hide() should clear the visible tabbar close watcher")

  ui.show()
  helpers.assert_truthy(handle_b:valid(), "show() should reopen the active hidden tab")
  helpers.assert_truthy(type(ui_tabbar.get_winid()) == "number", "show() should reopen the tabbar")

  local ok_set = select(1, ui.set_active_tab(first_tab_id))
  helpers.assert_truthy(ok_set, "set_active_tab() should accept registered tabs")
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "set_active_tab() should update active selection")
  helpers.assert_truthy(handle_a:valid(), "set_active_tab() should swap visible content when ui is open")
  helpers.assert_truthy(not handle_b:valid(), "set_active_tab() should hide the previously visible tab")

  local ok_move = select(1, ui.move_tab(second_tab_id, -1))
  helpers.assert_truthy(ok_move, "move_tab() should allow adjacent movement")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(ui_tabbar.get_winid()), { "T2", "T1" }), "move_tab() should rerender tabbar row order")
  helpers.assert_eq(select(1, ui.move_tab(second_tab_id, 0)), false, "move_tab() should reject invalid directions")

  local other_buf = vim.api.nvim_create_buf(false, true)
  local other_win = vim.api.nvim_open_win(other_buf, true, {
    relative = "editor",
    row = 2,
    col = 2,
    width = 12,
    height = 3,
    style = "minimal",
  })
  vim.wait(20, function()
    return ui_runtime.get_content_winid() == nil and ui_tabbar.get_winid() == nil
  end)
  helpers.assert_eq(ui_runtime.get_content_winid(), nil, "focus leave should still hide ui-owned tabs when focus moves away")
  helpers.assert_eq(ui_tabbar.get_winid(), nil, "focus leave should still hide the ui-owned tabbar when focus moves away")

  ui.show()
  local content_win = ui_runtime.get_content_winid()
  local tabbar_win = ui_tabbar.get_winid()

  helpers.assert_eq(vim.api.nvim_get_current_win(), other_win, "focus coverage should start outside qck windows")
  ui.toggle_tabbar_focus()
  helpers.assert_eq(vim.api.nvim_get_current_win(), content_win, "toggle_tabbar_focus() should focus content from a non-qck window")
  ui.toggle_tabbar_focus()
  helpers.assert_eq(vim.api.nvim_get_current_win(), tabbar_win, "toggle_tabbar_focus() should move focus from content to tabbar")
  ui.toggle_tabbar_focus()
  helpers.assert_eq(vim.api.nvim_get_current_win(), content_win, "toggle_tabbar_focus() should move focus back to content")

  ui.toggle_tabbar_focus()
  vim.api.nvim_set_current_win(tabbar_win)
  vim.api.nvim_win_set_cursor(tabbar_win, { 1, 0 })
  feed("<CR>")
  helpers.assert_eq(ui_state.resolve_active_tab(), second_tab_id, "tabbar <CR> should select the targeted ui tab")
  helpers.assert_truthy(handle_b:valid(), "tabbar <CR> should show the selected tab")
  helpers.assert_truthy(not handle_a:valid(), "tabbar <CR> should hide the previously active tab")
  helpers.assert_eq(vim.api.nvim_get_current_win(), ui_runtime.get_content_winid(), "tabbar <CR> should return focus to content")

  ui.toggle_tabbar_focus()
  vim.api.nvim_set_current_win(ui_tabbar.get_winid())
  feed("J")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(ui_tabbar.get_winid()), { "T1", "T2" }), "tabbar J should move the selected row through ui-owned ordering")

  local ok_reselect = select(1, ui.set_active_tab(first_tab_id))
  helpers.assert_truthy(ok_reselect, "set_active_tab() should still allow direct ui selection after tabbar actions")

  ui.delete_tab(first_tab_id)
  helpers.assert_eq(ui_state.resolve_active_tab(), second_tab_id, "delete_tab() should adopt the next live tab when deleting the active tab")
  helpers.assert_truthy(handle_b:valid(), "delete_tab() should show the adopted live tab when ui stays visible")
  helpers.assert_truthy(vim.deep_equal(tabbar_labels(ui_tabbar.get_winid()), { "T2" }), "delete_tab() should rerender the remaining tab rows")
  helpers.assert_eq(next(ui_runtime.get_owner_watchers(first_tab_id)), nil, "delete_tab() should clear per-tab watcher bookkeeping for deleted tabs")

  helpers.assert_eq(select(1, ui.set_active_tab(999)), false, "set_active_tab() should reject unknown tabs")
  helpers.assert_eq(select(1, ui.delete_tab(999)), false, "delete_tab() should reject unknown tabs")

  ui.delete_tab(second_tab_id)
  helpers.assert_eq(ui_state.resolve_active_tab(), nil, "deleting the last tab should clear active selection")
  helpers.assert_eq(ui_runtime.get_content_winid(), nil, "deleting the last tab should hide content")
  helpers.assert_eq(ui_tabbar.get_winid(), nil, "deleting the last tab should hide the tabbar")

  ui_tabbar.hide()
  ui_state.reset()
  ui_runtime.reset()
  helpers.assert_truthy(ui.register_category({ key = "terminal", label = "T" }), "rollback coverage should reuse category registration")

  local failing_handle = snacks.terminal.open(nil, { count = 3 })
  failing_handle:toggle()
  failing_handle.show = function()
    error("boom")
  end

  local failed_tab_id, attach_err = ui.attach_and_show("terminal", failing_handle)
  helpers.assert_eq(failed_tab_id, nil, "attach_and_show() should fail when initial show fails")
  helpers.assert_truthy(type(attach_err) == "string" and attach_err:find("boom", 1, true) ~= nil, "attach_and_show() should surface show errors")
  helpers.assert_truthy(vim.deep_equal(ui_state.traversal_ids(), {}), "failed attach_and_show() should leave no registered tabs behind")
  helpers.assert_eq(ui_state.get_active_tab_id(), nil, "failed attach_and_show() should roll back the active tab")
  helpers.assert_eq(ui_runtime.get_content_winid(), nil, "failed attach_and_show() should leave no content window tracked")
  helpers.assert_eq(ui_tabbar.get_winid(), nil, "failed attach_and_show() should leave no tabbar visible")
  helpers.assert_eq(ui_runtime.get_handle_owner(failing_handle), nil, "failed attach_and_show() should not transfer handle ownership")

  ui_tabbar.hide()
  ui_state.reset()
  ui_runtime.reset()
  ui.setup()
  helpers.assert_truthy(ui.register_category({ key = "terminal", label = "T" }), "late rollback coverage should register category")

  ui.set_terminal_user_mappings({ gx = ":quit<CR>" })
  ui.apply_terminal_user_mappings()

  local stable_handle = snacks.terminal.open(nil, { count = 4 })
  local stable_tab_id = select(1, ui.attach_and_show("terminal", stable_handle))
  helpers.assert_truthy(stable_tab_id ~= nil, "late rollback coverage should seed a visible tab")

  local original_show_for_terminal = ui_tabbar.show_for_terminal
  local failing_late_handle = snacks.terminal.open(nil, { count = 5 })
  local failing_buf = failing_late_handle.buf
  local failing_win = nil

  failing_late_handle:toggle()

  ui_tabbar.show_for_terminal = function(terminal)
    original_show_for_terminal(terminal)
    if terminal == failing_late_handle then
      failing_win = tostring(terminal.win)
      error("late boom")
    end
  end

  local late_tab_id, late_err = ui.attach_and_show("terminal", failing_late_handle)
  ui_tabbar.show_for_terminal = original_show_for_terminal

  helpers.assert_eq(late_tab_id, nil, "attach_and_show() should fail when late handoff work errors")
  helpers.assert_truthy(type(late_err) == "string" and late_err:find("late boom", 1, true) ~= nil, "late attach failure should surface the late error")
  helpers.assert_truthy(stable_handle:valid(), "late attach rollback should restore the previously visible tab")
  helpers.assert_truthy(not failing_late_handle:valid(), "late attach rollback should hide the failed tab window")
  helpers.assert_eq(ui_state.resolve_active_tab(), stable_tab_id, "late attach rollback should restore the previous active selection")
  helpers.assert_truthy(vim.deep_equal(ui_state.traversal_ids(), { stable_tab_id }), "late attach rollback should keep only the original tab registered")
  helpers.assert_eq(ui_runtime.get_content_winid(), stable_handle.win, "late attach rollback should restore the original visible content winid")
  helpers.assert_truthy(type(ui_tabbar.get_winid()) == "number", "late attach rollback should restore the tabbar")
  helpers.assert_eq(ui_runtime.get_handle_owner(failing_late_handle), nil, "late attach rollback should clear failed handle ownership")
  helpers.assert_eq(next(ui_runtime.get_owner_watchers(stable_tab_id)) ~= nil, true, "late attach rollback should restore visible watcher bookkeeping")
  helpers.assert_eq(buf_has_mapping(failing_buf, "n", "gx"), false, "late attach rollback should clear failed handle normal-mode mappings")
  helpers.assert_eq(buf_has_mapping(failing_buf, "t", "gx"), false, "late attach rollback should clear failed handle terminal-mode mappings")
  helpers.assert_eq(
    any_qck_autocmd(function(item)
      return item.buffer == failing_buf or item.pattern == failing_win
    end),
    false,
    "late attach rollback should clear failed tab autocmd watchers"
  )
end

function scenarios.ui_mouse_tabbar_selection_contract()
  require("mock_snacks").install()

  local ui = require("qck.ui")
  local ui_state = require("qck.ui.state")
  local ui_runtime = require("qck.ui.runtime")
  local ui_tabbar = require("qck.ui.tabbar")
  local snacks = require("snacks")

  ui_tabbar.hide()
  ui_state.reset()
  ui_runtime.reset()
  ui.setup()

  helpers.assert_truthy(ui.register_category({ key = "terminal", label = "T" }), "mouse tabbar scenario should register categories")

  local handle_a = snacks.terminal.open(nil, { count = 1 })
  attach_terminal_job(handle_a)
  local first_tab_id = select(1, ui.attach_and_show("terminal", handle_a))
  local handle_b = snacks.terminal.open(nil, { count = 2 })
  attach_terminal_job(handle_b)
  local second_tab_id = select(1, ui.attach_and_show("terminal", handle_b))
  helpers.assert_truthy(first_tab_id ~= nil and second_tab_id ~= nil, "mouse tabbar scenario should register tabs")
  helpers.assert_truthy(select(1, ui.set_active_tab(first_tab_id)), "mouse tabbar scenario should reselect the first tab")

  local tabbar_win = ui_tabbar.get_winid()
  local content_win = ui_runtime.get_content_winid()
  local tabbar_buf = vim.api.nvim_win_get_buf(tabbar_win)
  local content_buf = vim.api.nvim_win_get_buf(content_win)

  helpers.assert_truthy(buf_has_mapping(tabbar_buf, "n", "<LeftRelease>"), "tabbar should install a left-release mapping")
  helpers.assert_truthy(buf_has_mapping(content_buf, "n", "<LeftRelease>"), "content should install a normal-mode left-release mapping")
  helpers.assert_truthy(buf_has_mapping(content_buf, "t", "<LeftRelease>"), "content should install a terminal-mode left-release mapping")

  vim.api.nvim_set_current_win(content_win)
  ui_tabbar.handle_left_click({
    winid = tabbar_win,
    line = 2,
    screenrow = vim.fn.screenpos(tabbar_win, 2, 1).row,
  })
  helpers.assert_eq(ui_state.resolve_active_tab(), second_tab_id, "tabbar mouse should select the targeted tab from content focus")
  helpers.assert_truthy(handle_b:valid(), "tabbar mouse should show the clicked tab from content focus")
  helpers.assert_truthy(not handle_a:valid(), "tabbar mouse should hide the previous tab from content focus")
  helpers.assert_eq(vim.api.nvim_get_current_win(), handle_b.win, "tabbar mouse should focus the clicked terminal")
  assert_terminal_mode(vim.api.nvim_get_mode().mode, "tabbar mouse should enter terminal mode for the clicked terminal")

  local active_before_blank_click = ui_state.resolve_active_tab()
  local visible_before_blank_click = ui_runtime.get_content_winid()
  local focused_before_blank_click = vim.api.nvim_get_current_win()
  local mode_before_blank_click = vim.api.nvim_get_mode().mode
  tabbar_win = ui_tabbar.get_winid()
  ui_tabbar.handle_left_click({
    winid = tabbar_win,
    line = 2,
    screenrow = vim.fn.screenpos(tabbar_win, 2, 1).row + 1,
  })
  helpers.assert_eq(ui_state.resolve_active_tab(), active_before_blank_click, "tabbar clicks outside rendered rows should be ignored")
  helpers.assert_eq(ui_runtime.get_content_winid(), visible_before_blank_click, "blank tabbar clicks should preserve visible content")
  helpers.assert_eq(vim.api.nvim_get_current_win(), focused_before_blank_click, "blank tabbar clicks should preserve focus")
  helpers.assert_eq(vim.api.nvim_get_mode().mode, mode_before_blank_click, "blank tabbar clicks should preserve mode")

  vim.api.nvim_set_current_win(ui_tabbar.get_winid())
  vim.cmd("startinsert")
  vim.wait(20, function() return false end)
  ui_tabbar.handle_left_click({
    winid = ui_tabbar.get_winid(),
    line = 1,
    screenrow = vim.fn.screenpos(ui_tabbar.get_winid(), 1, 1).row,
  })
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "tabbar mouse should still select while escaping insert mode")
  helpers.assert_eq(vim.api.nvim_get_current_win(), handle_a.win, "tabbar mouse should focus the clicked terminal after insert mode")
  assert_terminal_mode(vim.api.nvim_get_mode().mode, "tabbar mouse should enter terminal mode after tabbar insert mode")

  vim.api.nvim_set_current_win(ui_tabbar.get_winid())
  vim.cmd("stopinsert")
  feed("j")
  feed("<CR>")
  helpers.assert_eq(ui_state.resolve_active_tab(), second_tab_id, "tabbar <CR> should still work after a mouse selection")
  helpers.assert_eq(vim.api.nvim_get_current_win(), ui_runtime.get_content_winid(), "tabbar <CR> should still return focus to content after mouse selection")

  pcall(vim.cmd, "stopinsert")
  helpers.cleanup_terminals(ui, ui_state, ui_tabbar)
end

function scenarios.terminals_and_layout()
  local env = helpers.load_qck()
  local qck, ui, ui_state, tabbar, layout =
    env.qck, env.ui, env.ui_state, env.tabbar, env.layout
  local ui_runtime = require("qck.ui.runtime")
  local expected = helpers.expected_layout(layout)

  qck.open()
  local first_tab_id = ui_state.resolve_active_tab()
  local first_tab = first_tab_id and ui_state.get_tab(first_tab_id) or nil
  local first_handle = first_tab and first_tab.terminal or nil
  local first_lookup = first_handle and ui_state.get_tab_by_terminal(first_handle) or nil
  helpers.assert_truthy(first_tab_id ~= nil, "open() should create one terminal when none exist")
  helpers.assert_truthy(first_tab and first_handle and first_handle.win, "open() should create a terminal window when none exist")
  helpers.assert_eq(first_lookup and first_lookup.id, first_tab_id, "open() should register the terminal through ui state")
  helpers.assert_eq(ui_runtime.get_handle_owner(first_handle), first_tab_id, "ui runtime should own the terminal handle after handoff")
  helpers.assert_eq(first_tab.category_display_id, 1, "first terminal should use T1 label")
  helpers.assert_window_layout(first_handle.win, tabbar.get_winid(), expected, "open() creation layout")
  assert_ids(ui_state.traversal_ids(), { first_tab_id }, "single terminal should seed ordered tabs")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1" }, "tabbar should render the initial terminal label")

  qck.new()
  local second_tab_id = ui_state.resolve_active_tab()
  local second_tab = second_tab_id and ui_state.get_tab(second_tab_id) or nil
  local second_handle = second_tab and second_tab.terminal or nil
  helpers.assert_truthy(second_tab_id ~= nil, "second new() should create a terminal tab")
  helpers.assert_truthy(second_tab and second_handle and second_handle.win, "second new() should create second terminal window")
  helpers.assert_truthy(not handle_is_open(first_handle), "creating another terminal should hide the previous terminal window")
  helpers.assert_window_layout(second_handle.win, tabbar.get_winid(), expected, "second terminal layout")
  assert_ids(ui_state.traversal_ids(), { first_tab_id, second_tab_id }, "new terminals should append to the single terminal order")
  helpers.assert_eq(second_tab.category_display_id, 2, "second terminal should use T2 label")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T2" }, "tabbar should render generic T labels")

  qck.cycle_prev()
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "cycle_prev() should make the first tab active")
  helpers.assert_truthy(handle_is_open(first_handle), "cycle_prev() should open the first terminal")
  helpers.assert_truthy(not handle_is_open(second_handle), "cycle_prev() should hide the previously visible terminal")

  qck.toggle()
  helpers.assert_truthy(not handle_is_open(first_handle), "toggle() should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "toggle() should hide the tabbar with the terminal")

  qck.open()
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "open() should target the active terminal")
  helpers.assert_truthy(handle_is_open(first_handle), "open() should re-open the hidden active terminal")
  helpers.assert_truthy(not handle_is_open(second_handle), "open() should hide the previously visible terminal")
  helpers.assert_window_layout(first_handle.win, tabbar.get_winid(), expected, "open() layout")

  qck.new()
  local third_tab_id = ui_state.resolve_active_tab()
  local third_tab = third_tab_id and ui_state.get_tab(third_tab_id) or nil
  local third_handle = third_tab and third_tab.terminal or nil
  helpers.assert_truthy(third_tab_id ~= nil, "third new() should create a terminal tab")
  helpers.assert_truthy(third_tab and third_handle and third_handle.win, "third new() should create third terminal window")
  assert_ids(ui_state.traversal_ids(), { first_tab_id, second_tab_id, third_tab_id }, "ordered tabs should track all live terminals")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T2", "T3" }, "tabbar should render all live terminals")

  local moved_up = select(1, ui.move_tab(third_tab_id, -1))
  helpers.assert_truthy(moved_up, "ui.move_tab() should reorder generic terminals upward")
  assert_ids(ui_state.traversal_ids(), { first_tab_id, third_tab_id, second_tab_id }, "moving a terminal up should update the shared terminal order")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T3", "T2" }, "tabbar should reflect reordered terminal rows")

  local moved_down = select(1, ui.move_tab(third_tab_id, 1))
  helpers.assert_truthy(moved_down, "ui.move_tab() should reorder generic terminals downward")
  assert_ids(ui_state.traversal_ids(), { first_tab_id, second_tab_id, third_tab_id }, "moving a terminal down should restore the original order")

  qck.cycle_prev()
  helpers.assert_eq(ui_state.resolve_active_tab(), second_tab_id, "cycle_prev() should follow the generic terminal order")
  helpers.assert_truthy(handle_is_open(second_handle), "cycle_prev() should open the second terminal")
  helpers.assert_truthy(not handle_is_open(third_handle), "cycle_prev() should hide the previously visible terminal")
  qck.cycle_next()
  helpers.assert_eq(ui_state.resolve_active_tab(), third_tab_id, "cycle_next() should wrap back through the generic terminal order")
  helpers.assert_truthy(handle_is_open(third_handle), "cycle_next() should reopen the third terminal")
  helpers.assert_truthy(not handle_is_open(second_handle), "cycle_next() should hide the previously visible terminal")

  helpers.assert_truthy(select(1, ui.set_active_tab(second_tab_id)), "ui.set_active_tab() should switch to the second terminal before deletion")
  helpers.assert_truthy(handle_is_open(second_handle), "ui.set_active_tab() should show the second terminal before deletion")
  ui.delete_tab(second_tab_id)
  helpers.assert_eq(ui_state.get_tab(second_tab_id), nil, "ui.delete_tab() should remove the requested terminal record")
  assert_ids(ui_state.traversal_ids(), { first_tab_id, third_tab_id }, "ui.delete_tab() should remove the terminal from the shared order")
  helpers.assert_eq(ui_state.resolve_active_tab(), third_tab_id, "ui.delete_tab() should adopt the next live terminal from UI traversal")
  helpers.assert_truthy(not handle_is_open(second_handle), "ui.delete_tab() should hide the deleted terminal window")
  helpers.assert_truthy(handle_is_open(third_handle), "ui.delete_tab() should show the adopted terminal while the UI is visible")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T3" }, "ui.delete_tab() should keep stable labels after delete")
  helpers.assert_eq(ui_state.get_tab(first_tab_id).category_display_id, 1, "existing terminal labels should remain stable after delete")
  helpers.assert_eq(ui_state.get_tab(third_tab_id).category_display_id, 3, "existing terminal labels should remain stable after delete")

  qck.new()
  local reused_tab_id = ui_state.resolve_active_tab()
  local reused_tab = reused_tab_id and ui_state.get_tab(reused_tab_id) or nil
  local reused_handle = reused_tab and reused_tab.terminal or nil
  helpers.assert_truthy(reused_tab_id ~= nil, "new() should create a replacement terminal tab")
  helpers.assert_truthy(reused_tab and reused_tab.category_display_id == 2, "new terminals should reuse the lowest missing label id")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T3", "T2" }, "recreated terminals should keep stable labels for survivors")

  helpers.assert_truthy(select(1, ui.set_active_tab(third_tab_id)), "ui.set_active_tab() should switch to the third terminal")
  helpers.assert_truthy(handle_is_open(third_handle), "ui.set_active_tab() should show the third terminal")
  helpers.assert_truthy(not handle_is_open(reused_handle), "ui.set_active_tab() should hide the previously visible terminal")

  qck.toggle()
  helpers.assert_truthy(not handle_is_open(third_handle), "toggle() should hide the current terminal window before reopen-by-open coverage")

  qck.open()
  helpers.assert_truthy(handle_is_open(third_handle), "open() should reopen the hidden active terminal")
  helpers.assert_window_layout(third_handle.win, tabbar.get_winid(), expected, "open() reopen layout")

  qck.close()
  helpers.assert_eq(ui_state.get_tab(third_tab_id), nil, "close() should remove the active terminal")
  helpers.assert_eq(ui_state.resolve_active_tab(), reused_tab_id, "close() should keep selection on the ui traversal fallback")
  helpers.assert_truthy(handle_is_open(reused_handle), "close() should show the adopted traversal fallback when ui is visible")
  helpers.assert_truthy(not handle_is_open(first_handle), "close() should only target the active terminal window")
  helpers.assert_truthy(type(tabbar.get_winid()) == "number", "close() should keep the tabbar open when deleting the active terminal")

  qck.toggle()
  helpers.assert_eq(ui_state.resolve_active_tab(), reused_tab_id, "toggle() should keep the adopted traversal fallback selected")
  qck.close()
  helpers.assert_eq(ui_state.get_tab(reused_tab_id), nil, "close() should delete the active terminal even when it is hidden")
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "close() should keep traversal fallback selection after deleting a hidden active terminal")
  helpers.assert_truthy(not handle_is_open(first_handle), "close() should not reopen fallback terminals when deleting a hidden active terminal")
  helpers.assert_eq(tabbar.get_winid(), nil, "close() should keep the ui hidden when deleting a hidden active terminal")

  helpers.cleanup_terminals(ui, ui_state, tabbar)

  helpers.set_editor_size(101, 45)
  expected = helpers.expected_layout(layout)
  qck.new()

  local odd_tab_id = ui_state.resolve_active_tab()
  local odd_tab = odd_tab_id and ui_state.get_tab(odd_tab_id) or nil
  local odd_rec = odd_tab and odd_tab.terminal or nil
  local odd_tab_win = tabbar.get_winid()
  helpers.assert_truthy(odd_tab_id ~= nil and odd_rec and odd_rec.win, "odd-dimension layout should create terminal window")
  helpers.assert_truthy(type(odd_tab_win) == "number", "odd-dimension layout should create tabbar window")
  helpers.assert_window_layout(odd_rec.win, odd_tab_win, expected, "odd-dimension layout")

  helpers.cleanup_terminals(ui, ui_state, tabbar)

  local function assert_resize_persists_geometry(start_columns, start_lines, end_columns, end_lines, msg_prefix)
    helpers.set_editor_size(start_columns, start_lines)
    qck.new()

    local current_tab_id = ui_state.resolve_active_tab()
    local current_tab = current_tab_id and ui_state.get_tab(current_tab_id) or nil
    local rec = current_tab and current_tab.terminal or nil
    local tab_win = tabbar.get_winid()
    helpers.assert_truthy(current_tab_id ~= nil and rec and rec.win, msg_prefix .. ": resize case should create terminal window")
    helpers.assert_truthy(type(tab_win) == "number", msg_prefix .. ": resize case should create tabbar window")

    vim.o.columns = end_columns
    vim.o.lines = end_lines
    vim.api.nvim_exec_autocmds("VimResized", {})
    helpers.force_full_footprint_terminal(rec.win)

    local bad_snapshot = helpers.capture_window_layout(rec.win, tab_win)
    local expected_after_resize = helpers.expected_layout(layout)
    helpers.assert_truthy(
      bad_snapshot.term_width ~= expected_after_resize.total_width - expected_after_resize.tabbar_width - expected_after_resize.gap_width
        or bad_snapshot.term_col ~= expected_after_resize.horizontal_margin
          + expected_after_resize.tabbar_width
          + expected_after_resize.gap_width
        or bad_snapshot.term_row ~= expected_after_resize.vertical_margin,
      msg_prefix .. ": simulated resize bug should produce a different fixed-margin footprint before deferred repair"
    )

    vim.wait(20, function() return false end)

    current_tab = current_tab_id and ui_state.get_tab(current_tab_id) or nil
    rec = current_tab and current_tab.terminal or nil
    tab_win = tabbar.get_winid()
    helpers.assert_truthy(
      current_tab_id ~= nil and rec and rec.win,
      msg_prefix .. ": resize case should keep terminal window open after deferred repair"
    )
    helpers.assert_truthy(type(tab_win) == "number", msg_prefix .. ": resize case should keep tabbar window open after deferred repair")

    local expected_after_wait = helpers.expected_layout(layout)
    helpers.assert_window_layout(rec.win, tab_win, expected_after_wait, msg_prefix)

    local resized_snapshot = helpers.capture_window_layout(rec.win, tab_win)

    qck.toggle()
    helpers.assert_truthy(not handle_is_open(rec), msg_prefix .. ": toggle should hide the resized terminal")

    qck.open()

    current_tab = current_tab_id and ui_state.get_tab(current_tab_id) or nil
    local reopened_rec = current_tab and current_tab.terminal or nil
    local reopened_tab_win = tabbar.get_winid()
    helpers.assert_truthy(current_tab_id ~= nil and reopened_rec and reopened_rec.win, msg_prefix .. ": reopen should restore terminal window")
    helpers.assert_truthy(type(reopened_tab_win) == "number", msg_prefix .. ": reopen should restore tabbar window")
    helpers.assert_layout_snapshot_eq(
      helpers.capture_window_layout(reopened_rec.win, reopened_tab_win),
      resized_snapshot,
      msg_prefix
    )

    helpers.cleanup_terminals(ui, ui_state, tabbar)
  end

  assert_resize_persists_geometry(80, 30, 160, 50, "resize small-to-large")
  assert_resize_persists_geometry(160, 50, 80, 30, "resize large-to-small")
end

function scenarios.terminal_lifecycle_watchers_and_focus()
  local env = helpers.load_qck()
  local qck, ui, ui_state, tabbar = env.qck, env.ui, env.ui_state, env.tabbar

  qck.open()
  local current_tab_id = ui_state.resolve_active_tab()
  local current_tab = current_tab_id and ui_state.get_tab(current_tab_id) or nil
  local rec = current_tab and current_tab.terminal or nil
  helpers.assert_truthy(current_tab_id ~= nil and rec and rec.win, "open() should create a visible terminal for lifecycle coverage")
  helpers.assert_truthy(type(tabbar.get_winid()) == "number", "open() should create a visible tabbar for lifecycle coverage")

  local term_win = rec.win
  vim.api.nvim_win_close(term_win, true)
  helpers.assert_truthy(ui_state.get_tab(current_tab_id) ~= nil, "manual terminal close should keep recoverable terminal record")
  helpers.assert_truthy(not handle_is_open(rec), "manual terminal close should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "manual terminal close should hide the tabbar window")

  qck.open()
  current_tab = current_tab_id and ui_state.get_tab(current_tab_id) or nil
  rec = current_tab and current_tab.terminal or nil
  local reopened_term_win = rec and rec.win or nil
  local reopened_tab_win = tabbar.get_winid()
  helpers.assert_truthy(type(reopened_term_win) == "number", "open() should reopen a recoverable hidden terminal")
  helpers.assert_truthy(type(reopened_tab_win) == "number", "open() should reopen the tabbar after manual terminal close")

  vim.api.nvim_win_close(reopened_tab_win, true)
  vim.wait(20, function()
    return not handle_is_open(rec) and tabbar.get_winid() == nil
  end)
  helpers.assert_truthy(not handle_is_open(rec), "manual tabbar close should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "manual tabbar close should leave no tabbar window open")
  helpers.assert_truthy(ui_state.get_tab(current_tab_id) ~= nil, "manual tabbar close should keep the current terminal recoverable")

  qck.open()
  current_tab = current_tab_id and ui_state.get_tab(current_tab_id) or nil
  rec = current_tab and current_tab.terminal or nil
  reopened_term_win = rec and rec.win or nil
  reopened_tab_win = tabbar.get_winid()
  helpers.assert_truthy(type(reopened_term_win) == "number", "open() should reopen the terminal after manual tabbar close")
  helpers.assert_truthy(type(reopened_tab_win) == "number", "open() should reopen the tabbar after manual tabbar close")

  local other_win = vim.api.nvim_get_current_win()
  qck.switch_focus()
  helpers.assert_eq(vim.api.nvim_get_current_win(), reopened_term_win, "switch_focus() should focus the terminal from a non-qck window")
  qck.switch_focus()
  helpers.assert_eq(vim.api.nvim_get_current_win(), reopened_tab_win, "switch_focus() should move focus from terminal to tabbar")
  qck.switch_focus()
  helpers.assert_eq(vim.api.nvim_get_current_win(), reopened_term_win, "switch_focus() should move focus back from tabbar to terminal")

  vim.api.nvim_set_current_win(other_win)
  vim.wait(20, function()
    return not handle_is_open(rec) and tabbar.get_winid() == nil
  end)
  helpers.assert_truthy(not handle_is_open(rec), "focus leave should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "focus leave should hide the tabbar window")
  helpers.assert_truthy(ui_state.get_tab(current_tab_id) ~= nil, "focus leave should keep the current terminal recoverable")
end

function scenarios.terminal_invalidation_and_active_fallbacks()
  local env = helpers.load_qck()
  local qck, ui, ui_state, tabbar = env.qck, env.ui, env.ui_state, env.tabbar

  qck.open()
  local first_tab_id = ui_state.resolve_active_tab()
  local first_tab = first_tab_id and ui_state.get_tab(first_tab_id) or nil
  local first_rec = first_tab and first_tab.terminal or nil

  qck.new()
  local second_tab_id = ui_state.resolve_active_tab()
  local second_tab = second_tab_id and ui_state.get_tab(second_tab_id) or nil
  local second_rec = second_tab and second_tab.terminal or nil

  helpers.assert_eq(first_tab and first_tab.category_display_id, 1, "open() should create T1 before fallback coverage")
  helpers.assert_eq(second_tab and second_tab.category_display_id, 2, "new() should create T2 before fallback coverage")
  helpers.assert_truthy(not handle_is_open(first_rec), "creating another terminal should hide the first terminal before fallback coverage")
  helpers.assert_truthy(handle_is_open(second_rec), "second terminal should be visible before fallback coverage")

  ui_state.set_active_tab_id(999)
  qck.open()
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "open() should adopt the first live terminal when the active id is stale")
  helpers.assert_truthy(handle_is_open(first_rec), "open() should reopen the adopted live terminal")
  helpers.assert_truthy(not handle_is_open(second_rec), "open() should hide the previously visible terminal after stale-active fallback")

  ui_state.set_active_tab_id(999)
  qck.toggle()
  helpers.assert_eq(ui_state.resolve_active_tab(), first_tab_id, "toggle() should adopt the first live terminal when the active id is stale")
  helpers.assert_truthy(not handle_is_open(first_rec), "toggle() should hide the adopted live terminal")
  helpers.assert_eq(tabbar.get_winid(), nil, "toggle() stale-active fallback hide should close the tabbar")

  helpers.cleanup_terminals(ui, ui_state, tabbar)
  qck.toggle()
  local created_tab_id = ui_state.resolve_active_tab()
  local created_tab = created_tab_id and ui_state.get_tab(created_tab_id) or nil
  local created_rec = created_tab and created_tab.terminal or nil
  helpers.assert_truthy(created_tab and created_tab.category_display_id == 1, "toggle() should create the lowest missing terminal label when no terminals exist")
  helpers.assert_truthy(created_tab_id ~= nil and handle_is_open(created_rec), "toggle() should create and show a terminal in the empty state")
  helpers.assert_truthy(type(tabbar.get_winid()) == "number", "toggle() empty-state creation should also show the tabbar")

  local active_buf = created_rec.buf
  vim.api.nvim_buf_delete(active_buf, { force = true })
  helpers.assert_eq(ui_state.get_tab(created_tab_id), nil, "BufWipeout should remove the invalid terminal record")
  helpers.assert_eq(ui_state.resolve_active_tab(), nil, "BufWipeout should clear the active tab when the last terminal is invalidated")
  helpers.assert_eq(tabbar.get_winid(), nil, "BufWipeout should leave no tabbar visible when the last terminal is invalidated")
end

function scenarios.clear_storage()
  local env = helpers.load_qck()
  local qck, storage, workspace = env.qck, env.storage, env.workspace

  storage.set_task_cmd(workspace, "compile", "echo compile")
  local ok = storage.save()
  helpers.assert_truthy(ok, "workspace task should be created")

  qck.clear_storage()
  local ok_load_after_clear = storage.load()
  helpers.assert_truthy(ok_load_after_clear, "storage should load after clear_storage()")
  helpers.assert_eq(storage.get_task_cmd(workspace, "compile"), nil, "clear_storage() should clear workspace data")
end

function scenarios.invalid_storage_repair()
  local env = helpers.load_qck()
  local qck, storage, workspace = env.qck, env.storage, env.workspace

  helpers.write_storage({
    version = "0.1.0",
    workspaces = {
      [workspace] = {
        bad = {},
      },
    },
  })

  local ok_invalid = storage.load()
  helpers.assert_eq(ok_invalid, false, "unsupported storage shape should fail load")

  qck.clear_storage()
  local ok_after_repair = storage.load()
  helpers.assert_truthy(ok_after_repair, "clear_storage() should restore valid storage state")
end

function scenarios.ordered()
  return {
    { name = "task form | creates and overwrites workspace task", run = scenarios.task_form_create_and_overwrite },
    { name = "task form | edits existing workspace task", run = scenarios.task_form_edit_existing_task },
    { name = "task runner | selects workspace task", run = scenarios.task_runner_selects_workspace_task },
    { name = "task runner | reorders workspace tasks", run = scenarios.task_runner_reorders_workspace_tasks },
    { name = "task runner | edits selected task", run = scenarios.task_runner_edits_selected_task },
    { name = "task runner | edit is no-op for empty workspace", run = scenarios.task_runner_edit_empty_workspace_noops },
    { name = "task runner | handles empty workspace", run = scenarios.task_runner_empty_workspace },
    { name = "storage | persists workspace task commands across load/save", run = scenarios.storage_roundtrip },
    { name = "storage | stores task creation order numbers", run = scenarios.storage_task_ordering },
    { name = "storage | moves task order numbers", run = scenarios.storage_task_order_moves },
    { name = "storage | persists across module reload", run = scenarios.storage_persists_across_module_reload },
    { name = "storage | creates missing data dir on save", run = scenarios.storage_save_creates_missing_data_dir },
    { name = "storage | writes empty object maps", run = scenarios.storage_empty_state_writes_object_maps },
    { name = "ui state | registers categories and traverses tabs", run = scenarios.ui_state_registration_and_traversal },
    { name = "ui runtime | tracks windows, handles, and layout scaffolding", run = scenarios.ui_runtime_and_layout_scaffolding },
    { name = "ui tabbar | renders from ui-owned traversal and active state", run = scenarios.ui_tabbar_renders_from_ui_state },
    { name = "ui init | manages internal ui orchestration and rollback", run = scenarios.ui_init_orchestration_contract },
    { name = "terminals | manages generic terminals with shared layout", run = scenarios.terminals_and_layout },
    { name = "terminals | preserves lifecycle watcher behavior and focus routing", run = scenarios.terminal_lifecycle_watchers_and_focus },
    { name = "terminals | keeps finished task terminal open", run = scenarios.task_terminal_finish_keeps_task_tab_open },
    { name = "terminals | preserves mixed terminal tabbar after task finish", run = scenarios.task_terminal_finish_preserves_mixed_tabbar },
    { name = "terminals | pins task terminals before regular terminals", run = scenarios.task_terminals_are_pinned_before_regular_terminals },
    { name = "terminals | skips tabbar kind divider", run = scenarios.tabbar_skips_kind_divider },
    { name = "terminals | reuses existing task terminal", run = scenarios.task_runner_reuses_existing_task_terminal },
    { name = "terminals | reopens hidden matching task terminal", run = scenarios.task_runner_reopens_hidden_matching_task_terminal },
    { name = "terminals | creates task terminals for distinct commands", run = scenarios.task_runner_spawns_distinct_task_terminals_for_distinct_commands },
    { name = "terminals | uses task order for K labels", run = scenarios.task_runner_uses_task_order_for_k_labels },
    { name = "terminals | updates K labels after task reorder", run = scenarios.task_runner_updates_k_labels_after_reorder },
    { name = "terminals | prunes invalid terminals and adopts live fallbacks", run = scenarios.terminal_invalidation_and_active_fallbacks },
    { name = "storage | clears workspace data for current workspace", run = scenarios.clear_storage },
    { name = "storage | fails invalid load and repairs storage through clear_storage", run = scenarios.invalid_storage_repair },
  }
end

return scenarios
