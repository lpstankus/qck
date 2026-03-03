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
  local tasks = require("qck.tasks")
  local storage = require("qck.storage")
  local task_form = require("qck.task_form")
  local workspace = vim.fn.getcwd()

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

  qck.close(restarted_compile_id)
  assert(state.get_terminal(restarted_compile_id) == nil, "close(id) should remove terminal record")

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
