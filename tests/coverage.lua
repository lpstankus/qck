local root = vim.fn.getcwd()
local coverage_dir = root .. "/tests/.coverage"

vim.fn.mkdir(coverage_dir, "p")
vim.fn.delete(root .. "/tests/.coverage/luacov.stats.out")
vim.fn.delete(root .. "/tests/.coverage/luacov.report.out")
vim.o.showmode = false

package.path = table.concat({
  root .. "/tests/vendor/luacov/src/?.lua",
  root .. "/tests/vendor/luacov/src/?/init.lua",
  root .. "/?.lua",
  root .. "/?/init.lua",
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/tests/?.lua",
  package.path,
}, ";")

require("bootstrap").setup_xdg("coverage")
vim.env.QCK_TEST_SNACKS_RTP = nil

require("luacov")

local helpers = require("helpers")
local scenarios = require("scenarios")
local runner = require("luacov.runner")

local ok, err = pcall(function()
  for _, scenario in ipairs(scenarios.ordered()) do
    helpers.reset_environment()
    local scenario_ok, scenario_err = xpcall(scenario.run, debug.traceback)
    helpers.reset_environment()
    if not scenario_ok then
      error(scenario_err)
    end
  end
end)

runner.shutdown()

if not ok then
  vim.api.nvim_err_writeln("qck coverage run failed: " .. tostring(err))
  vim.cmd("cquit 1")
  return
end

vim.cmd("qa")
