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

function scenarios.task_form_create_and_overwrite()
  local env = helpers.load_qck()
  local qck, storage, task_form, workspace =
    env.qck, env.storage, env.task_form, env.workspace

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
end

function scenarios.terminals_and_layout()
  local env = helpers.load_qck()
  local qck, state, terminal, tabbar, layout =
    env.qck, env.state, env.terminal, env.tabbar, env.layout
  local expected = helpers.expected_layout(layout)

  qck.open()
  helpers.assert_eq(#state.live_ids(), 1, "open() should create one terminal when none exist")
  helpers.assert_eq(state.get_current_id(), 1, "open() should set current id when creating the first terminal")

  local default_rec = state.get_terminal(1)
  helpers.assert_truthy(default_rec and default_rec.win and default_rec.win.win, "open() should create a terminal window when none exist")
  helpers.assert_window_layout(default_rec.win.win, tabbar.get_winid(), expected, "open() creation layout")
  assert_ids(state.ordered_ids(), { 1 }, "single terminal should seed ordered ids")
  helpers.assert_eq(state.get_label_id(1), 1, "first terminal should use T1 label")

  qck.new()
  local second_id = state.get_current_id()
  local second_rec = state.get_terminal(second_id)
  helpers.assert_eq(second_id, 2, "second new() should create terminal 2")
  helpers.assert_truthy(second_rec and second_rec.win and second_rec.win.win, "second new() should create second terminal window")
  helpers.assert_truthy(not state.is_window_open(default_rec), "creating another terminal should hide the previous terminal window")
  helpers.assert_window_layout(second_rec.win.win, tabbar.get_winid(), expected, "second terminal layout")
  assert_ids(state.ordered_ids(), { 1, 2 }, "new terminals should append to the single terminal order")
  helpers.assert_eq(state.get_label_id(2), 2, "second terminal should use T2 label")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T2" }, "tabbar should render generic T labels")

  qck.cycle_prev()
  helpers.assert_eq(state.get_current_id(), 1, "cycle_prev() should make terminal 1 active")
  helpers.assert_truthy(state.is_window_open(default_rec), "cycle_prev() should open terminal 1")
  helpers.assert_truthy(not state.is_window_open(second_rec), "cycle_prev() should hide the previously visible terminal")

  qck.toggle()
  helpers.assert_truthy(not state.is_window_open(default_rec), "toggle() should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "toggle() should hide the tabbar with the terminal")

  qck.open()
  helpers.assert_eq(state.get_current_id(), 1, "open() should target the active terminal")
  helpers.assert_truthy(state.is_window_open(default_rec), "open() should re-open the hidden active terminal")
  helpers.assert_truthy(not state.is_window_open(second_rec), "open() should hide the previously visible terminal")
  helpers.assert_window_layout(default_rec.win.win, tabbar.get_winid(), expected, "open() layout")

  qck.new()
  local third_id = state.get_current_id()
  local third_rec = state.get_terminal(third_id)
  helpers.assert_eq(third_id, 3, "third new() should create terminal 3")
  helpers.assert_truthy(third_rec and third_rec.win and third_rec.win.win, "third new() should create third terminal window")
  assert_ids(state.ordered_ids(), { 1, 2, 3 }, "ordered ids should track all live terminals")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T2", "T3" }, "tabbar should render all live terminals")

  local moved_up = terminal.move_up(3)
  helpers.assert_truthy(moved_up, "move_up() should reorder generic terminals")
  assert_ids(state.ordered_ids(), { 1, 3, 2 }, "move_up() should update the shared terminal order")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T3", "T2" }, "tabbar should reflect reordered terminal rows")

  local moved_down = terminal.move_down(3)
  helpers.assert_truthy(moved_down, "move_down() should reorder generic terminals")
  assert_ids(state.ordered_ids(), { 1, 2, 3 }, "move_down() should restore the original order")

  qck.cycle_prev()
  helpers.assert_eq(state.get_current_id(), 2, "cycle_prev() should follow the generic terminal order")
  qck.cycle_next()
  helpers.assert_eq(state.get_current_id(), 3, "cycle_next() should wrap back through the generic terminal order")

  terminal.delete(2)
  helpers.assert_eq(state.get_terminal(2), nil, "delete() should remove the requested terminal record")
  assert_ids(state.ordered_ids(), { 1, 3 }, "delete() should remove the terminal from the shared order")
  helpers.assert_eq(state.get_label_id(1), 1, "existing terminal labels should remain stable after delete")
  helpers.assert_eq(state.get_label_id(3), 3, "existing terminal labels should remain stable after delete")

  qck.new()
  local reused_id = state.get_current_id()
  helpers.assert_eq(reused_id, 2, "new() should reuse the lowest missing terminal id")
  helpers.assert_eq(state.get_label_id(reused_id), 2, "new terminals should reuse the lowest missing label id")
  assert_ids(tabbar_labels(tabbar.get_winid()), { "T1", "T3", "T2" }, "recreated terminals should keep stable labels for survivors")

  terminal.open(3)
  qck.toggle()
  helpers.assert_truthy(
    not state.is_window_open(state.get_terminal(3)),
    "toggle() should hide the current terminal window before reopen-by-open coverage"
  )

  qck.open()
  local reopened_by_open = state.get_terminal(3)
  helpers.assert_truthy(
    reopened_by_open and reopened_by_open.win and reopened_by_open.win.win,
    "open() should reopen the hidden active terminal"
  )
  helpers.assert_window_layout(reopened_by_open.win.win, tabbar.get_winid(), expected, "open() reopen layout")

  qck.close()
  helpers.assert_eq(state.get_terminal(3), nil, "close() should remove the active terminal")
  helpers.assert_eq(state.get_current_id(), 1, "close() should keep selection on the remaining active fallback")
  helpers.assert_truthy(not state.is_window_open(state.get_terminal(1)), "close() should only target the active terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "close() should hide the tabbar when the active terminal closes")

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
        or bad_snapshot.term_col ~= expected_after_resize.horizontal_margin
          + expected_after_resize.tabbar_width
          + expected_after_resize.gap_width
        or bad_snapshot.term_row ~= expected_after_resize.vertical_margin,
      msg_prefix .. ": simulated resize bug should produce a different fixed-margin footprint before deferred repair"
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

    state.set_current_id(current_id)
    qck.open()

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

function scenarios.terminal_lifecycle_watchers_and_focus()
  local env = helpers.load_qck()
  local qck, state, tabbar = env.qck, env.state, env.tabbar

  qck.open()
  local current_id = state.get_current_id()
  local rec = state.get_terminal(current_id)
  helpers.assert_truthy(rec and rec.win and rec.win.win, "open() should create a visible terminal for lifecycle coverage")
  helpers.assert_truthy(type(tabbar.get_winid()) == "number", "open() should create a visible tabbar for lifecycle coverage")

  local term_win = rec.win.win
  vim.api.nvim_win_close(term_win, true)
  helpers.assert_truthy(state.get_terminal(current_id) == rec, "manual terminal close should keep recoverable terminal record")
  helpers.assert_truthy(not state.is_window_open(rec), "manual terminal close should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "manual terminal close should hide the tabbar window")

  qck.open()
  rec = state.get_terminal(current_id)
  local reopened_term_win = rec and rec.win and rec.win.win or nil
  local reopened_tab_win = tabbar.get_winid()
  helpers.assert_truthy(type(reopened_term_win) == "number", "open() should reopen a recoverable hidden terminal")
  helpers.assert_truthy(type(reopened_tab_win) == "number", "open() should reopen the tabbar after manual terminal close")

  vim.api.nvim_win_close(reopened_tab_win, true)
  vim.wait(20, function()
    return not state.is_window_open(rec) and tabbar.get_winid() == nil
  end)
  helpers.assert_truthy(not state.is_window_open(rec), "manual tabbar close should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "manual tabbar close should leave no tabbar window open")
  helpers.assert_truthy(state.is_valid_record(rec), "manual tabbar close should keep the current terminal recoverable")

  qck.open()
  rec = state.get_terminal(current_id)
  reopened_term_win = rec and rec.win and rec.win.win or nil
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
    return not state.is_window_open(rec) and tabbar.get_winid() == nil
  end)
  helpers.assert_truthy(not state.is_window_open(rec), "focus leave should hide the current terminal window")
  helpers.assert_eq(tabbar.get_winid(), nil, "focus leave should hide the tabbar window")
  helpers.assert_truthy(state.is_valid_record(rec), "focus leave should keep the current terminal recoverable")
end

function scenarios.terminal_invalidation_and_active_fallbacks()
  local env = helpers.load_qck()
  local qck, state, tabbar = env.qck, env.state, env.tabbar

  qck.open()
  local first_id = state.get_current_id()
  local first_rec = state.get_terminal(first_id)

  qck.new()
  local second_id = state.get_current_id()
  local second_rec = state.get_terminal(second_id)

  helpers.assert_eq(first_id, 1, "open() should create T1 before fallback coverage")
  helpers.assert_eq(second_id, 2, "new() should create T2 before fallback coverage")
  helpers.assert_truthy(not state.is_window_open(first_rec), "creating another terminal should hide the first terminal before fallback coverage")
  helpers.assert_truthy(state.is_window_open(second_rec), "second terminal should be visible before fallback coverage")

  state.set_current_id(999)
  qck.open()
  helpers.assert_eq(state.get_current_id(), first_id, "open() should adopt the first live terminal when the active id is stale")
  helpers.assert_truthy(state.is_window_open(first_rec), "open() should reopen the adopted live terminal")
  helpers.assert_truthy(not state.is_window_open(second_rec), "open() should hide the previously visible terminal after stale-active fallback")
  helpers.assert_eq(state.get_terminal(999), nil, "open() should not create a replacement terminal for a stale active id")

  state.set_current_id(999)
  qck.toggle()
  helpers.assert_eq(state.get_current_id(), first_id, "toggle() should adopt the first live terminal when the active id is stale")
  helpers.assert_truthy(not state.is_window_open(first_rec), "toggle() should hide the adopted live terminal")
  helpers.assert_eq(state.get_terminal(999), nil, "toggle() should not create a replacement terminal for a stale active id")
  helpers.assert_eq(tabbar.get_winid(), nil, "toggle() stale-active fallback hide should close the tabbar")

  helpers.cleanup_terminals(env.terminal, state, tabbar)
  qck.toggle()
  local created_id = state.get_current_id()
  local created_rec = state.get_terminal(created_id)
  helpers.assert_eq(created_id, 1, "toggle() should create the lowest missing terminal when no terminals exist")
  helpers.assert_truthy(created_rec and state.is_window_open(created_rec), "toggle() should create and show a terminal in the empty state")
  helpers.assert_truthy(type(tabbar.get_winid()) == "number", "toggle() empty-state creation should also show the tabbar")

  local active_buf = created_rec.win.buf
  vim.api.nvim_buf_delete(active_buf, { force = true })
  helpers.assert_eq(state.get_terminal(created_id), nil, "BufWipeout should remove the invalid terminal record")
  helpers.assert_eq(state.get_current_id(), nil, "BufWipeout should clear the active id when the last terminal is invalidated")
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
    { name = "storage | persists workspace task commands across load/save", run = scenarios.storage_roundtrip },
    { name = "terminals | manages generic terminals with shared layout", run = scenarios.terminals_and_layout },
    { name = "terminals | preserves lifecycle watcher behavior and focus routing", run = scenarios.terminal_lifecycle_watchers_and_focus },
    { name = "terminals | prunes invalid terminals and adopts live fallbacks", run = scenarios.terminal_invalidation_and_active_fallbacks },
    { name = "storage | clears workspace data for current workspace", run = scenarios.clear_storage },
    { name = "storage | fails invalid load and repairs storage through clear_storage", run = scenarios.invalid_storage_repair },
  }
end

return scenarios
