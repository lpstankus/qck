local root = vim.fn.getcwd()
vim.env.XDG_DATA_HOME = root .. "/tests/.tmp/minitest-data"
vim.o.showmode = false

vim.opt.rtp:prepend(root .. "/tests/vendor/mini.nvim")

package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/tests/?.lua",
  package.path,
}, ";")

local minitest = require("mini.test")

if _G.MiniTest == nil then
  minitest.setup({
    script_path = root .. "/tests/_no_project_script.lua",
    execute = {
      reporter = minitest.gen_reporter.stdout({ quit_on_finish = false }),
    },
  })
end

minitest.run({
  collect = {
    find_files = function()
      return { root .. "/tests/test_smoke.lua" }
    end,
  },
})

local has_fails = false
for _, case in ipairs(MiniTest.current.all_cases or {}) do
  if type(case.exec) == "table" and case.exec.state == "Fail" then
    has_fails = true
    break
  end
end

vim.cmd(("silent! %dcquit"):format(has_fails and 1 or 0))
