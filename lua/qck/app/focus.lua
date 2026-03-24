-- Thin compatibility wiring during the UI handoff migration.
--
-- Global focus/resize watchers now live in `qck.ui`. This module keeps only the
-- tabbar action bridge so existing setup/import paths continue to work while the
-- remaining terminal row actions still resolve through terminal ids.
local terminal = require("qck.terminal.service")
local tabbar = require("qck.terminal.tabbar")
local ui = require("qck.ui")

local focus = {}

local initialized = false

function focus.setup()
  if initialized then
    return
  end
  initialized = true

  tabbar.set_actions({
    open = function(id) terminal.open(id) end,
    delete = function(id) terminal.delete(id) end,
    move_up = function(id) terminal.move_up(id) end,
    move_down = function(id) terminal.move_down(id) end,
    close_current = function() ui.hide() end,
    focus_current = function() ui.toggle_tabbar_focus() end,
  })

  ui.setup()
end
return focus
