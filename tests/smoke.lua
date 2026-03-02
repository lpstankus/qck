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

  qck.setup()

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
  local workspace = vim.fn.getcwd()
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
