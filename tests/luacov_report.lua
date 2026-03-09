local root = vim.fn.getcwd()

package.path = table.concat({
  root .. "/tests/vendor/luacov/src/?.lua",
  root .. "/tests/vendor/luacov/src/?/init.lua",
  package.path,
}, ";")

local runner = require("luacov.runner")
local config = runner.load_config(root .. "/.luacov")
runner.run_report(config)
