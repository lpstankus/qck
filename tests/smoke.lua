package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./tests/?.lua;" .. package.path

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(("%s (expected %s, got %s)"):format(msg, tostring(expected), tostring(actual)))
  end
end

local function assert_truthy(value, msg)
  if not value then
    error(msg)
  end
end

local function to_int(value)
  return math.floor(tonumber(value) or 0)
end

local function get_expected_layout(layout)
  local expected_tabbar_width = layout.get_tabbar_width()
  local expected_gap_width = layout.get_window_gap_width()
  local expected_total_width = math.min(
    vim.o.columns,
    math.max(expected_tabbar_width + expected_gap_width + 1, math.ceil(vim.o.columns * 0.9))
  )
  local expected_total_height = math.min(
    vim.o.lines,
    math.max(1, math.ceil(vim.o.lines * 0.9))
  )

  return {
    tabbar_width = expected_tabbar_width,
    gap_width = expected_gap_width,
    total_width = expected_total_width,
    total_height = expected_total_height,
  }
end

local function capture_window_layout(term_win, tab_win)
  local term_cfg = vim.api.nvim_win_get_config(term_win)
  local tab_cfg = vim.api.nvim_win_get_config(tab_win)

  return {
    term_row = to_int(term_cfg.row),
    term_col = to_int(term_cfg.col),
    term_width = vim.api.nvim_win_get_width(term_win),
    term_height = vim.api.nvim_win_get_height(term_win),
    tab_row = to_int(tab_cfg.row),
    tab_col = to_int(tab_cfg.col),
    tab_width = vim.api.nvim_win_get_width(tab_win),
    tab_height = vim.api.nvim_win_get_height(tab_win),
  }
end

local function assert_layout_snapshot_eq(actual, expected, msg_prefix)
  assert_eq(actual.term_row, expected.term_row, msg_prefix .. ": terminal row should stay stable")
  assert_eq(actual.term_col, expected.term_col, msg_prefix .. ": terminal col should stay stable")
  assert_eq(actual.term_width, expected.term_width, msg_prefix .. ": terminal width should stay stable")
  assert_eq(actual.term_height, expected.term_height, msg_prefix .. ": terminal height should stay stable")
  assert_eq(actual.tab_row, expected.tab_row, msg_prefix .. ": tabbar row should stay stable")
  assert_eq(actual.tab_col, expected.tab_col, msg_prefix .. ": tabbar col should stay stable")
  assert_eq(actual.tab_width, expected.tab_width, msg_prefix .. ": tabbar width should stay stable")
  assert_eq(actual.tab_height, expected.tab_height, msg_prefix .. ": tabbar height should stay stable")
end

local function force_full_footprint_terminal(term_win)
  local term_cfg = vim.api.nvim_win_get_config(term_win)
  local full_width = math.min(vim.o.columns, math.max(1, math.ceil(vim.o.columns * 0.9)))
  local full_height = math.min(vim.o.lines, math.max(1, math.ceil(vim.o.lines * 0.9)))

  term_cfg.relative = "editor"
  term_cfg.col = math.max(0, math.floor((vim.o.columns - full_width) / 2))
  term_cfg.row = math.max(0, math.floor((vim.o.lines - full_height) / 2))
  term_cfg.width = full_width
  term_cfg.height = full_height

  vim.api.nvim_win_set_config(term_win, term_cfg)
end

local function set_editor_size(columns, lines)
  vim.o.columns = columns
  vim.o.lines = lines
  vim.api.nvim_exec_autocmds("VimResized", {})
  vim.wait(20, function() return false end)
end

local function cleanup_terminals(terminal, state, tabbar)
  local ids = state.live_ids()
  for _, id in ipairs(ids) do
    terminal.delete(id)
  end
  tabbar.hide()
end

local function assert_window_layout(
  term_win,
  tab_win,
  expected_total_width,
  expected_total_height,
  expected_tabbar_width,
  expected_gap_width,
  msg_prefix
)
  local term_cfg = vim.api.nvim_win_get_config(term_win)
  local tab_cfg = vim.api.nvim_win_get_config(tab_win)
  local border_footprint = 2
  local term_col = to_int(term_cfg.col)
  local tab_col = to_int(tab_cfg.col)
  local term_width = vim.api.nvim_win_get_width(term_win)
  local tab_width = vim.api.nvim_win_get_width(tab_win)
  local term_height = vim.api.nvim_win_get_height(term_win)
  local tab_height = vim.api.nvim_win_get_height(tab_win)
  local expected_base_col = math.max(0, math.floor((vim.o.columns - (expected_total_width + border_footprint)) / 2))
  local expected_base_row = math.max(0, math.floor((vim.o.lines - (expected_total_height + border_footprint)) / 2))

  assert_eq(tab_width, expected_tabbar_width, msg_prefix .. ": tabbar width should match shared width")
  assert_eq(
    term_width,
    expected_total_width - expected_tabbar_width - expected_gap_width,
    msg_prefix .. ": terminal width should shrink by tabbar width and gap"
  )
  assert_eq(tab_col, expected_base_col, msg_prefix .. ": tabbar should anchor to the footprint left edge")
  assert_eq(
    term_col,
    expected_base_col + expected_tabbar_width + expected_gap_width,
    msg_prefix .. ": terminal should shift right by tabbar width and gap"
  )
  assert_eq(to_int(tab_cfg.row), expected_base_row, msg_prefix .. ": tabbar should anchor to the footprint top edge")
  assert_eq(to_int(term_cfg.row), expected_base_row, msg_prefix .. ": terminal should share the footprint top edge")
  assert_eq(term_col - (tab_col + tab_width), expected_gap_width, msg_prefix .. ": tabbar gap should match configured spacing")
  assert_eq(
    term_width + tab_width + expected_gap_width,
    expected_total_width,
    msg_prefix .. ": combined width plus gap should match the terminal footprint"
  )
  assert_eq(term_height, expected_total_height, msg_prefix .. ": terminal height should match shared height")
  assert_eq(tab_height, expected_total_height, msg_prefix .. ": tabbar height should match shared height")
  assert_eq(
    vim.o.columns - (tab_col + expected_total_width + border_footprint),
    vim.o.columns - (expected_total_width + border_footprint) - expected_base_col,
    msg_prefix .. ": horizontal remainder should stay on the right"
  )
  assert_eq(
    vim.o.lines - (to_int(tab_cfg.row) + expected_total_height + border_footprint),
    vim.o.lines - (expected_total_height + border_footprint) - expected_base_row,
    msg_prefix .. ": vertical remainder should stay on the bottom"
  )
end

local function write_storage(data)
  local path = vim.fn.stdpath("data") .. "/qck.json"
  vim.fn.writefile({ vim.json.encode(data) }, path)
end

local function set_form_fields(buf, name_line, cmd_line)
  vim.api.nvim_buf_set_lines(buf, 2, 4, false, {
    name_line,
    cmd_line,
  })
end

local function assert_form_scaffold(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert_eq(#lines, 6, "task form should render six scaffold lines")
  assert_eq(lines[1], "Please provide the name and command of the new task", "task form should render description")
  assert_truthy(vim.startswith(lines[3], "Name    | "), "task form should render name field prefix")
  assert_truthy(vim.startswith(lines[4], "Command | "), "task form should render command field prefix")
  assert_eq(lines[6], "<Tab>/<S-Tab> switch  <CR> save  <Esc> close", "task form should render help line")
end

local function run()
  local mock_snacks = require("mock_snacks")
  mock_snacks.install()

  write_storage({
    version = "0.1.0",
    workspaces = {},
  })

  local qck = require("qck")
  local state = require("qck.state")
  local terminal = require("qck.terminal")
  local tasks = require("qck.tasks")
  local storage = require("qck.storage")
  local task_form = require("qck.task_form")
  local tabbar = require("qck.tabbar")
  local layout = require("qck.layout")
  local workspace = vim.fn.getcwd()
  local expected_layout = get_expected_layout(layout)

  qck.setup()

  qck.new_task()
  local form_win = task_form.get_winid()
  assert_truthy(type(form_win) == "number", "new_task() should open task form window")
  qck.new_task()
  assert_eq(task_form.get_winid(), form_win, "new_task() should focus existing task form window")
  local form_buf = vim.api.nvim_win_get_buf(form_win)
  assert_eq(vim.bo[form_buf].filetype, "qck-task-form", "task form should set filetype")
  assert_form_scaffold(form_buf)

  set_form_fields(form_buf, "Name: lint", "Command: echo lint")
  task_form.submit()
  assert_eq(task_form.get_winid(), nil, "task form should close after successful create")
  assert_truthy(tasks.has_definition("lint"), "created task should register as task definition")
  assert_eq(storage.get_task_cmd(workspace, "lint"), "echo lint", "created task command should persist")

  qck.new_task()
  form_win = task_form.get_winid()
  assert_truthy(type(form_win) == "number", "second new_task() should open task form")
  form_buf = vim.api.nvim_win_get_buf(form_win)
  set_form_fields(form_buf, "Name: lint", "Command: echo lint 2")
  task_form.submit()
  assert_truthy(task_form.get_winid() ~= nil, "first duplicate save should require confirmation")
  assert_eq(
    storage.get_task_cmd(workspace, "lint"),
    "echo lint",
    "first duplicate save should not overwrite existing task"
  )
  form_buf = vim.api.nvim_win_get_buf(task_form.get_winid())
  set_form_fields(form_buf, "Name: ", "Command: echo lint 2")
  task_form.submit()
  assert_truthy(task_form.get_winid() ~= nil, "empty name validation should keep task form open")
  set_form_fields(form_buf, "Name: lint", "Command: echo lint 2")
  task_form.submit()
  assert_truthy(
    task_form.get_winid() ~= nil,
    "changing form contents after duplicate warning should require overwrite confirmation again"
  )
  assert_eq(
    storage.get_task_cmd(workspace, "lint"),
    "echo lint",
    "duplicate overwrite confirmation should not persist before second submit"
  )
  task_form.submit()
  assert_eq(task_form.get_winid(), nil, "second duplicate save should close task form")
  assert_eq(
    storage.get_task_cmd(workspace, "lint"),
    "echo lint 2",
    "second duplicate save should overwrite existing task"
  )

  tasks.set_definitions({})
  assert_eq(tasks.has_definition("lint"), false, "set_definitions() should reset configured task definitions")
  local hydrated_count = tasks.hydrate_workspace_tasks(workspace)
  assert_eq(hydrated_count, 1, "hydrate_workspace_tasks() should add stored task definitions")
  assert_truthy(tasks.has_definition("lint"), "hydration should restore workspace-created task")

  tasks.set_storage(storage)
  tasks.set_definitions({
    compile = { cmd = { "echo", "compile" }, auto_scroll = true },
    server = { cmd = "echo server", auto_scroll = false },
  })

  qck.new()
  assert_eq(#state.live_ids(), 1, "new() should create one terminal")
  assert_eq(state.get_current_id(), 1, "new() should set current id")
  assert_eq(state.is_task(1), false, "new() terminal should be default kind")
  local default_rec = state.get_terminal(1)
  assert_truthy(default_rec and default_rec.win and default_rec.win.win, "new() should create a terminal window")
  assert_window_layout(
    default_rec.win.win,
    tabbar.get_winid(),
    expected_layout.total_width,
    expected_layout.total_height,
    expected_layout.tabbar_width,
    expected_layout.gap_width,
    "new() layout"
  )

  tasks.run("compile")
  local compile_id = tasks.get_running_id("compile")
  assert(type(compile_id) == "number", "tasks.run() should start task terminal")
  assert_truthy(state.get_terminal(compile_id) ~= nil, "task terminal should exist")
  assert_eq(state.is_task(compile_id), true, "task terminal kind should be task")

  tasks.run("compile")
  assert_eq(
    tasks.get_running_id("compile"),
    compile_id,
    "tasks.run() should reuse running task by default"
  )

  tasks.run("compile", { force_new = true })
  local restarted_compile_id = tasks.get_running_id("compile")
  assert(type(restarted_compile_id) == "number", "force_new should leave compile task running")

  tasks.run("server")
  local server_id = tasks.get_running_id("server")
  assert(type(server_id) == "number", "second task type should run concurrently")
  assert(server_id ~= restarted_compile_id, "different task types should use different terminals")

  qck.open(restarted_compile_id)
  assert_eq(state.get_current_id(), restarted_compile_id, "open(id) should focus requested terminal")

  qck.toggle()
  assert(
    not state.is_window_open(state.get_terminal(restarted_compile_id)),
    "toggle() should hide current terminal window"
  )
  qck.toggle()
  assert(
    state.is_window_open(state.get_terminal(restarted_compile_id)),
    "toggle() should re-open current terminal window"
  )
  local reopened_compile_rec = state.get_terminal(restarted_compile_id)
  assert_truthy(reopened_compile_rec and reopened_compile_rec.win and reopened_compile_rec.win.win, "toggle() should reopen terminal window")
  assert_window_layout(
    reopened_compile_rec.win.win,
    tabbar.get_winid(),
    expected_layout.total_width,
    expected_layout.total_height,
    expected_layout.tabbar_width,
    expected_layout.gap_width,
    "toggle() reopen layout"
  )

  tasks.kill("server")
  assert(
    tasks.get_running_id("server") == nil,
    "tasks.kill() should remove running task terminal"
  )

  tasks.set_task_cmd("compile", { "echo", "override" })
  assert_truthy(storage.get_task_cmd(workspace, "compile") ~= nil, "task override should persist")

  qck.clear_storage()
  local ok_load_after_clear = storage.load()
  assert_truthy(ok_load_after_clear, "storage should load after clear_storage()")
  assert_eq(storage.get_task_cmd(workspace, "compile"), nil, "clear_storage() should clear workspace data")

  write_storage({
    version = "0.1.0",
    workspaces = {
      [workspace] = {
        bad = {},
      },
    },
  })

  local ok_invalid = storage.load()
  assert_eq(ok_invalid, false, "unsupported storage shape should fail load")

  qck.clear_storage()
  local ok_after_repair = storage.load()
  assert_truthy(ok_after_repair, "clear_storage() should restore valid storage state")

  qck.open(restarted_compile_id)
  qck.toggle()
  assert(
    not state.is_window_open(state.get_terminal(restarted_compile_id)),
    "toggle() should hide the current terminal window before reopen-by-open coverage"
  )
  qck.open(restarted_compile_id)
  local reopened_by_open = state.get_terminal(restarted_compile_id)
  assert_truthy(reopened_by_open and reopened_by_open.win and reopened_by_open.win.win, "open(id) should reopen hidden terminal")
  assert_window_layout(
    reopened_by_open.win.win,
    tabbar.get_winid(),
    expected_layout.total_width,
    expected_layout.total_height,
    expected_layout.tabbar_width,
    expected_layout.gap_width,
    "open(id) reopen layout"
  )

  cleanup_terminals(terminal, state, tabbar)

  set_editor_size(101, 45)
  expected_layout = get_expected_layout(layout)
  qck.new()
  local odd_id = state.get_current_id()
  local odd_rec = state.get_terminal(odd_id)
  local odd_tab_win = tabbar.get_winid()
  assert_truthy(odd_rec and odd_rec.win and odd_rec.win.win, "odd-dimension layout should create terminal window")
  assert_truthy(type(odd_tab_win) == "number", "odd-dimension layout should create tabbar window")
  assert_window_layout(
    odd_rec.win.win,
    odd_tab_win,
    expected_layout.total_width,
    expected_layout.total_height,
    expected_layout.tabbar_width,
    expected_layout.gap_width,
    "odd-dimension layout"
  )

  cleanup_terminals(terminal, state, tabbar)

  local function assert_resize_persists_geometry(start_columns, start_lines, end_columns, end_lines, msg_prefix)
    set_editor_size(start_columns, start_lines)
    qck.new()

    local current_id = state.get_current_id()
    local rec = state.get_terminal(current_id)
    local tab_win = tabbar.get_winid()
    assert_truthy(rec and rec.win and rec.win.win, msg_prefix .. ": resize case should create terminal window")
    assert_truthy(type(tab_win) == "number", msg_prefix .. ": resize case should create tabbar window")

    vim.o.columns = end_columns
    vim.o.lines = end_lines
    vim.api.nvim_exec_autocmds("VimResized", {})
    force_full_footprint_terminal(rec.win.win)

    local bad_snapshot = capture_window_layout(rec.win.win, tab_win)
    local expected_after_resize = get_expected_layout(layout)
    assert_truthy(
      bad_snapshot.term_width ~= expected_after_resize.total_width - expected_after_resize.tabbar_width - expected_after_resize.gap_width
          or bad_snapshot.term_col ~= math.max(
            0,
            math.floor((vim.o.columns - (expected_after_resize.total_width + 2)) / 2)
          )
              + expected_after_resize.tabbar_width + expected_after_resize.gap_width,
      msg_prefix .. ": simulated resize bug should produce a different terminal footprint before deferred repair"
    )

    vim.wait(20, function() return false end)

    rec = state.get_terminal(current_id)
    tab_win = tabbar.get_winid()
    assert_truthy(rec and rec.win and rec.win.win, msg_prefix .. ": resize case should keep terminal window open after deferred repair")
    assert_truthy(type(tab_win) == "number", msg_prefix .. ": resize case should keep tabbar window open after deferred repair")

    local expected = get_expected_layout(layout)
    assert_window_layout(
      rec.win.win,
      tab_win,
      expected.total_width,
      expected.total_height,
      expected.tabbar_width,
      expected.gap_width,
      msg_prefix
    )

    local resized_snapshot = capture_window_layout(rec.win.win, tab_win)

    qck.toggle()
    assert_truthy(not state.is_window_open(rec), msg_prefix .. ": toggle should hide the resized terminal")

    qck.open(current_id)

    local reopened_rec = state.get_terminal(current_id)
    local reopened_tab_win = tabbar.get_winid()
    assert_truthy(reopened_rec and reopened_rec.win and reopened_rec.win.win, msg_prefix .. ": reopen should restore terminal window")
    assert_truthy(type(reopened_tab_win) == "number", msg_prefix .. ": reopen should restore tabbar window")
    assert_layout_snapshot_eq(
      capture_window_layout(reopened_rec.win.win, reopened_tab_win),
      resized_snapshot,
      msg_prefix
    )

    cleanup_terminals(terminal, state, tabbar)
  end

  assert_resize_persists_geometry(80, 30, 160, 50, "resize small-to-large")
  assert_resize_persists_geometry(160, 50, 80, 30, "resize large-to-small")

  mock_snacks.reset()
end

local ok, err = pcall(run)
if not ok then
  vim.api.nvim_err_writeln("qck smoke failed: " .. tostring(err))
  vim.cmd("cquit 1")
  return
end

print("qck smoke passed")
vim.cmd("qa!")
