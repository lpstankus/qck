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

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
  vim.wait(20, function() return false end)
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
  helpers.assert_eq(ok_conflict, false, "ui state should reject conflicting re-registration")
  local ok_duplicate_label = state.register_category({ key = "notes", label = "T" })
  helpers.assert_eq(ok_duplicate_label, false, "ui state should reject duplicate category labels")

  local terminal_a = {}
  local terminal_b = {}
  local task_a = {}
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
  helpers.assert_eq(first_terminal.category_label, "T", "registered terminal should derive category label metadata")
  helpers.assert_eq(first_terminal.category_display_id, 1, "first terminal should use the first category display id")
  helpers.assert_eq(second_terminal.category_display_id, 2, "second terminal should increment the category display id")
  helpers.assert_eq(first_task.category_display_id, 1, "display ids should be scoped per category")
  helpers.assert_truthy(
    state.get_tab_by_terminal(terminal_a).id == first_terminal_id,
    "ui state should index tabs by their registered terminal handle"
  )
  helpers.assert_eq(select(1, state.register_tab("terminal", terminal_a)), nil, "ui state should reject duplicate terminal registration")

  helpers.assert_truthy(
    vim.deep_equal(state.category_tab_ids("terminal"), { first_terminal_id, second_terminal_id }),
    "ui state should keep per-category ordering"
  )
  helpers.assert_truthy(
    vim.deep_equal(state.traversal_ids(), { first_terminal_id, second_terminal_id, first_task_id }),
    "ui state should derive global traversal from category order and per-category order"
  )

  local moved_up = state.move_tab(second_terminal_id, -1)
  helpers.assert_truthy(moved_up, "ui state should allow adjacent category-local movement")
  helpers.assert_truthy(
    vim.deep_equal(state.category_tab_ids("terminal"), { second_terminal_id, first_terminal_id }),
    "ui state should update category-local order after movement"
  )
  helpers.assert_truthy(
    vim.deep_equal(state.traversal_ids(), { second_terminal_id, first_terminal_id, first_task_id }),
    "ui state traversal should follow category-local movement"
  )
  helpers.assert_eq(state.move_tab(second_terminal_id, -1), false, "ui state should no-op at a category boundary")

  local deleted = state.delete_tab(first_terminal_id)
  helpers.assert_truthy(deleted, "ui state should delete registered tabs")
  helpers.assert_eq(state.get_tab(first_terminal_id), nil, "ui state should remove deleted tabs from the registry")
  helpers.assert_eq(
    state.get_tab(second_terminal_id).category_display_id,
    2,
    "ui state should keep survivor display ids stable after delete"
  )

  local reused_terminal_id = select(1, state.register_tab("terminal", terminal_c))
  helpers.assert_eq(reused_terminal_id, 4, "ui state should not reuse deleted tab ids")
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
    vim.deep_equal(state.traversal_ids(), { second_terminal_id, reused_terminal_id, first_task_id }),
    "ui state should preserve global traversal after display-id reuse"
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
  runtime.set_tabbar_surface(tabbar_buf, tabbar_win)
  helpers.assert_eq(runtime.get_content_winid(), content_win, "ui runtime should track the visible content winid")
  helpers.assert_eq(runtime.get_tabbar_bufnr(), tabbar_buf, "ui runtime should track the tabbar bufnr")
  helpers.assert_eq(runtime.get_tabbar_winid(), tabbar_win, "ui runtime should track the tabbar winid")
  helpers.assert_truthy(runtime.is_visible(), "ui runtime should report visibility when content is open")

  local handle_a = {}
  local handle_b = {}
  helpers.assert_truthy(select(1, runtime.register_handle(1, handle_a)), "ui runtime should register owned handles")
  helpers.assert_eq(runtime.get_registered_handle(1), handle_a, "ui runtime should expose the registered handle by owner id")
  helpers.assert_eq(runtime.get_handle_owner(handle_a), 1, "ui runtime should reverse-index registered handles")
  helpers.assert_eq(select(1, runtime.register_handle(2, handle_a)), false, "ui runtime should reject duplicate handle ownership")
  helpers.assert_eq(select(1, runtime.register_handle(1, handle_b)), false, "ui runtime should reject conflicting owner re-registration")
  runtime.unregister_handle(1)
  helpers.assert_eq(runtime.get_registered_handle(1), nil, "ui runtime should unregister owned handles")

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
  ui_runtime.set_tabbar_surface(buf, win)

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

  local ok_delete = select(1, ui.delete_tab(first_tab_id))
  helpers.assert_truthy(ok_delete, "delete_tab() should remove registered tabs")
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
end

function scenarios.terminals_and_layout()
  local env = helpers.load_qck()
  local qck, state, terminal, tabbar, layout =
    env.qck, env.state, env.terminal, env.tabbar, env.layout
  local ui_runtime = require("qck.ui.runtime")
  local ui_state = require("qck.ui.state")
  local expected = helpers.expected_layout(layout)

  qck.open()
  helpers.assert_eq(#state.live_ids(), 1, "open() should create one terminal when none exist")
  helpers.assert_eq(state.get_current_id(), 1, "open() should set current id when creating the first terminal")

  local default_rec = state.get_terminal(1)
  helpers.assert_truthy(default_rec and default_rec.win and default_rec.win.win, "open() should create a terminal window when none exist")
  helpers.assert_truthy(type(state.get_tab_id(1)) == "number", "open() should register the terminal through ui state")
  helpers.assert_eq(ui_runtime.get_handle_owner(default_rec.win), state.get_tab_id(1), "ui runtime should own the terminal handle after handoff")
  helpers.assert_eq(ui_state.resolve_active_tab(), state.get_tab_id(1), "ui state should track the active terminal tab after handoff")
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

  state.set_current_id(second_id)
  qck.open()
  helpers.assert_eq(
    state.get_current_id(),
    1,
    "open() should follow ui-owned active selection instead of a stale terminal current-id hint"
  )
  helpers.assert_eq(ui_state.resolve_active_tab(), state.get_tab_id(1), "ui state should remain the active selection source")

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
  helpers.assert_eq(state.get_current_id(), 2, "close() should keep selection on the ui traversal fallback")
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
  local ui_state = require("qck.ui.state")

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

  ui_state.set_active_tab_id(999)
  qck.open()
  helpers.assert_eq(state.get_current_id(), first_id, "open() should adopt the first live terminal when the active id is stale")
  helpers.assert_truthy(state.is_window_open(first_rec), "open() should reopen the adopted live terminal")
  helpers.assert_truthy(not state.is_window_open(second_rec), "open() should hide the previously visible terminal after stale-active fallback")
  helpers.assert_eq(state.get_terminal(999), nil, "open() should not create a replacement terminal for a stale active id")

  ui_state.set_active_tab_id(999)
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
    { name = "ui state | registers categories and traverses tabs", run = scenarios.ui_state_registration_and_traversal },
    { name = "ui runtime | tracks windows, handles, and layout scaffolding", run = scenarios.ui_runtime_and_layout_scaffolding },
    { name = "ui tabbar | renders from ui-owned traversal and active state", run = scenarios.ui_tabbar_renders_from_ui_state },
    { name = "ui init | manages internal ui orchestration and rollback", run = scenarios.ui_init_orchestration_contract },
    { name = "terminals | manages generic terminals with shared layout", run = scenarios.terminals_and_layout },
    { name = "terminals | preserves lifecycle watcher behavior and focus routing", run = scenarios.terminal_lifecycle_watchers_and_focus },
    { name = "terminals | prunes invalid terminals and adopts live fallbacks", run = scenarios.terminal_invalidation_and_active_fallbacks },
    { name = "storage | clears workspace data for current workspace", run = scenarios.clear_storage },
    { name = "storage | fails invalid load and repairs storage through clear_storage", run = scenarios.invalid_storage_repair },
  }
end

return scenarios
