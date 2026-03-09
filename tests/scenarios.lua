local helpers = require("helpers")

local scenarios = {}

function scenarios.task_form_create_and_overwrite()
  local env = helpers.load_qck()
  local qck, tasks, storage, task_form, workspace =
    env.qck, env.tasks, env.storage, env.task_form, env.workspace

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
  helpers.assert_truthy(tasks.has_definition("lint"), "created task should register as task definition")
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
end

function scenarios.hydrate_workspace_tasks()
  local env = helpers.load_qck()
  local tasks = env.tasks

  local ok = tasks.create_workspace_task("lint", "echo lint")
  helpers.assert_truthy(ok, "workspace task should be created")

  tasks.set_definitions({})
  helpers.assert_eq(tasks.has_definition("lint"), false, "set_definitions() should reset configured task definitions")

  local hydrated_count = tasks.hydrate_workspace_tasks(env.workspace)
  helpers.assert_eq(hydrated_count, 1, "hydrate_workspace_tasks() should add stored task definitions")
  helpers.assert_truthy(tasks.has_definition("lint"), "hydration should restore workspace-created task")
end

function scenarios.terminals_and_layout()
  local env = helpers.load_qck()
  local qck, state, terminal, tasks, storage, tabbar, layout, workspace =
    env.qck, env.state, env.terminal, env.tasks, env.storage, env.tabbar, env.layout, env.workspace
  local expected = helpers.expected_layout(layout)

  tasks.set_storage(storage)
  tasks.set_definitions({
    compile = { cmd = { "echo", "compile" }, auto_scroll = true },
    server = { cmd = "echo server", auto_scroll = false },
  })

  qck.new()
  helpers.assert_eq(#state.live_ids(), 1, "new() should create one terminal")
  helpers.assert_eq(state.get_current_id(), 1, "new() should set current id")
  helpers.assert_eq(state.is_task(1), false, "new() terminal should be default kind")

  local default_rec = state.get_terminal(1)
  helpers.assert_truthy(default_rec and default_rec.win and default_rec.win.win, "new() should create a terminal window")
  helpers.assert_window_layout(default_rec.win.win, tabbar.get_winid(), expected, "new() layout")

  tasks.run("compile")
  local compile_id = tasks.get_running_id("compile")
  helpers.assert_truthy(type(compile_id) == "number", "tasks.run() should start task terminal")
  helpers.assert_truthy(state.get_terminal(compile_id) ~= nil, "task terminal should exist")
  helpers.assert_eq(state.is_task(compile_id), true, "task terminal kind should be task")

  tasks.run("compile")
  helpers.assert_eq(tasks.get_running_id("compile"), compile_id, "tasks.run() should reuse running task by default")

  tasks.run("compile", { force_new = true })
  local restarted_compile_id = tasks.get_running_id("compile")
  helpers.assert_truthy(type(restarted_compile_id) == "number", "force_new should leave compile task running")

  tasks.run("server")
  local server_id = tasks.get_running_id("server")
  helpers.assert_truthy(type(server_id) == "number", "second task type should run concurrently")
  helpers.assert_truthy(server_id ~= restarted_compile_id, "different task types should use different terminals")

  qck.open(restarted_compile_id)
  helpers.assert_eq(state.get_current_id(), restarted_compile_id, "open(id) should focus requested terminal")

  qck.toggle()
  helpers.assert_truthy(
    not state.is_window_open(state.get_terminal(restarted_compile_id)),
    "toggle() should hide current terminal window"
  )

  qck.toggle()
  helpers.assert_truthy(
    state.is_window_open(state.get_terminal(restarted_compile_id)),
    "toggle() should re-open current terminal window"
  )

  local reopened_compile_rec = state.get_terminal(restarted_compile_id)
  helpers.assert_truthy(
    reopened_compile_rec and reopened_compile_rec.win and reopened_compile_rec.win.win,
    "toggle() should reopen terminal window"
  )
  helpers.assert_window_layout(reopened_compile_rec.win.win, tabbar.get_winid(), expected, "toggle() reopen layout")

  tasks.kill("server")
  helpers.assert_eq(tasks.get_running_id("server"), nil, "tasks.kill() should remove running task terminal")

  tasks.set_task_cmd("compile", { "echo", "override" })
  helpers.assert_truthy(storage.get_task_cmd(workspace, "compile") ~= nil, "task override should persist")

  qck.open(restarted_compile_id)
  qck.toggle()
  helpers.assert_truthy(
    not state.is_window_open(state.get_terminal(restarted_compile_id)),
    "toggle() should hide the current terminal window before reopen-by-open coverage"
  )

  qck.open(restarted_compile_id)
  local reopened_by_open = state.get_terminal(restarted_compile_id)
  helpers.assert_truthy(
    reopened_by_open and reopened_by_open.win and reopened_by_open.win.win,
    "open(id) should reopen hidden terminal"
  )
  helpers.assert_window_layout(reopened_by_open.win.win, tabbar.get_winid(), expected, "open(id) reopen layout")

  helpers.cleanup_terminals(terminal, state, tabbar)

  helpers.set_editor_size(101, 45)
  expected = helpers.expected_layout(layout)
  qck.new()

  local odd_id = state.get_current_id()
  local odd_rec = state.get_terminal(odd_id)
  local odd_tab_win = tabbar.get_winid()
  helpers.assert_truthy(odd_rec and odd_rec.win and odd_rec.win.win, "odd-dimension layout should create terminal window")
  helpers.assert_truthy(type(odd_tab_win) == "number", "odd-dimension layout should create tabbar window")
  helpers.assert_window_layout(odd_rec.win.win, odd_tab_win, expected, "odd-dimension layout")

  helpers.cleanup_terminals(terminal, state, tabbar)

  local function assert_resize_persists_geometry(start_columns, start_lines, end_columns, end_lines, msg_prefix)
    helpers.set_editor_size(start_columns, start_lines)
    qck.new()

    local current_id = state.get_current_id()
    local rec = state.get_terminal(current_id)
    local tab_win = tabbar.get_winid()
    helpers.assert_truthy(rec and rec.win and rec.win.win, msg_prefix .. ": resize case should create terminal window")
    helpers.assert_truthy(type(tab_win) == "number", msg_prefix .. ": resize case should create tabbar window")

    vim.o.columns = end_columns
    vim.o.lines = end_lines
    vim.api.nvim_exec_autocmds("VimResized", {})
    helpers.force_full_footprint_terminal(rec.win.win)

    local bad_snapshot = helpers.capture_window_layout(rec.win.win, tab_win)
    local expected_after_resize = helpers.expected_layout(layout)
    helpers.assert_truthy(
      bad_snapshot.term_width ~= expected_after_resize.total_width - expected_after_resize.tabbar_width - expected_after_resize.gap_width
        or bad_snapshot.term_col ~= math.max(
          0,
          math.floor((vim.o.columns - (expected_after_resize.total_width + 2)) / 2)
        ) + expected_after_resize.tabbar_width + expected_after_resize.gap_width,
      msg_prefix .. ": simulated resize bug should produce a different terminal footprint before deferred repair"
    )

    vim.wait(20, function() return false end)

    rec = state.get_terminal(current_id)
    tab_win = tabbar.get_winid()
    helpers.assert_truthy(
      rec and rec.win and rec.win.win,
      msg_prefix .. ": resize case should keep terminal window open after deferred repair"
    )
    helpers.assert_truthy(type(tab_win) == "number", msg_prefix .. ": resize case should keep tabbar window open after deferred repair")

    local expected_after_wait = helpers.expected_layout(layout)
    helpers.assert_window_layout(rec.win.win, tab_win, expected_after_wait, msg_prefix)

    local resized_snapshot = helpers.capture_window_layout(rec.win.win, tab_win)

    qck.toggle()
    helpers.assert_truthy(not state.is_window_open(rec), msg_prefix .. ": toggle should hide the resized terminal")

    qck.open(current_id)

    local reopened_rec = state.get_terminal(current_id)
    local reopened_tab_win = tabbar.get_winid()
    helpers.assert_truthy(reopened_rec and reopened_rec.win and reopened_rec.win.win, msg_prefix .. ": reopen should restore terminal window")
    helpers.assert_truthy(type(reopened_tab_win) == "number", msg_prefix .. ": reopen should restore tabbar window")
    helpers.assert_layout_snapshot_eq(
      helpers.capture_window_layout(reopened_rec.win.win, reopened_tab_win),
      resized_snapshot,
      msg_prefix
    )

    helpers.cleanup_terminals(terminal, state, tabbar)
  end

  assert_resize_persists_geometry(80, 30, 160, 50, "resize small-to-large")
  assert_resize_persists_geometry(160, 50, 80, 30, "resize large-to-small")
end

function scenarios.clear_storage()
  local env = helpers.load_qck()
  local qck, tasks, storage, workspace = env.qck, env.tasks, env.storage, env.workspace

  local ok = tasks.create_workspace_task("compile", "echo compile")
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
    { name = "tasks | hydrates persisted workspace task definitions", run = scenarios.hydrate_workspace_tasks },
    { name = "terminals | manages default and task terminals with shared layout", run = scenarios.terminals_and_layout },
    { name = "storage | clears workspace data for current workspace", run = scenarios.clear_storage },
    { name = "storage | fails invalid load and repairs storage through clear_storage", run = scenarios.invalid_storage_repair },
  }
end

return scenarios
