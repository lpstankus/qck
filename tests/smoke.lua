package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./tests/?.lua;" .. package.path

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(("%s (expected %s, got %s)"):format(msg, tostring(expected), tostring(actual)))
  end
end

local function run()
  local mock_snacks = require("mock_snacks")
  mock_snacks.install()

  local qck = require("qck")
  local state = require("qck.state")

  qck.setup({
    builders = {
      build = { cmd = { "echo", "build" }, auto_scroll = true },
      server = { cmd = "echo server", auto_scroll = false },
    },
  })

  qck.new()
  assert_eq(#state.live_ids(), 1, "new() should create one terminal")
  assert_eq(state.get_current_id(), 1, "new() should set current id")

  qck.run({ "echo", "task" }, { id = 2 })
  assert(state.get_terminal(2) ~= nil, "run() should create terminal with requested id")
  assert(state.is_long_running(2), "run() terminals must be long_running")
  assert_eq(state.get_current_id(), 2, "run() should focus created terminal")

  qck.cycle_next()
  assert_eq(state.get_current_id(), 1, "cycle_next() should advance current terminal")
  qck.cycle_prev()
  assert_eq(state.get_current_id(), 2, "cycle_prev() should move back to previous terminal")

  qck.build("build")
  local build_id = state.find_terminal_id_by_builder_type("build")
  assert(type(build_id) == "number", "build() should start builder terminal")

  qck.build("build")
  assert_eq(
    state.find_terminal_id_by_builder_type("build"),
    build_id,
    "build() should reuse existing builder terminal by default"
  )

  qck.build("build", { force_new = true })
  local restarted_build_id = state.find_terminal_id_by_builder_type("build")
  assert(type(restarted_build_id) == "number", "force_new build() should restart builder terminal")

  qck.build("server")
  local server_id = state.find_terminal_id_by_builder_type("server")
  assert(type(server_id) == "number", "second builder type should run concurrently")
  assert(server_id ~= restarted_build_id, "different builder types should use different terminals")

  qck.open(restarted_build_id)
  assert_eq(state.get_current_id(), restarted_build_id, "open(id) should focus requested terminal")

  qck.toggle()
  assert(
    not state.is_window_open(state.get_terminal(restarted_build_id)),
    "toggle() should hide current terminal window"
  )
  qck.toggle()
  assert(
    state.is_window_open(state.get_terminal(restarted_build_id)),
    "toggle() should re-open current terminal window"
  )

  qck.kill_builder("server")
  assert(
    state.find_terminal_id_by_builder_type("server") == nil,
    "kill_builder() should remove running builder terminal"
  )

  qck.close(restarted_build_id)
  assert(state.get_terminal(restarted_build_id) == nil, "close(id) should remove terminal record")

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
