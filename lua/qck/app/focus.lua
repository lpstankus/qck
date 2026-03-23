-- Current pre-migration global focus/resize watcher wiring.
--
-- The target UI handoff contract is documented in
-- `plans/2-ui-handoff-contract.md`. These watchers still route directly to the
-- terminal/tabbar modules for focus-leave hide behavior and deferred resize
-- repair, but the documented migration target is UI-owned watcher behavior with
-- separate global and per-tab lifetimes.
local terminal = require("qck.terminal.service")
local tabbar = require("qck.terminal.tabbar")
local autocmd = require("qck.shared.autocmd")
local notify = require("qck.shared.notify").notify

local focus = {}

local focus_cleanup_in_progress = false
local resize_refresh_pending = false
local initialized = false

local function focus_current_terminal()
  local term_win = terminal.get_current_winid()
  if not term_win then
    return
  end
  vim.api.nvim_set_current_win(term_win)
end

local function hide_if_focus_left_qck_windows()
  if focus_cleanup_in_progress then
    return
  end

  local term_win = terminal.get_current_winid()
  local tab_win = tabbar.get_winid()
  if not term_win and not tab_win then
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  if (term_win and current_win == term_win) or (tab_win and current_win == tab_win) then
    return
  end

  focus_cleanup_in_progress = true

  local ok_term, term_err = pcall(function() terminal.hide_current_if_open() end)
  local ok_tabbar, tabbar_err = pcall(function() tabbar.hide() end)

  vim.schedule(function()
    focus_cleanup_in_progress = false
  end)

  if not ok_term then
    notify(("failed to hide qck terminal after focus left qck windows: %s"):format(tostring(term_err)), vim.log.levels.ERROR)
  end

  if not ok_tabbar then
    notify(("failed to hide qck tabbar after focus left qck windows: %s"):format(tostring(tabbar_err)), vim.log.levels.ERROR)
  end
end

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
    close_current = function() terminal.hide_current_if_open() end,
    focus_current = focus_current_terminal,
  })

  autocmd.create({ "WinEnter", "BufEnter", "TabEnter" }, {
    callback = hide_if_focus_left_qck_windows,
  })

  autocmd.create("VimResized", {
    callback = function()
      if resize_refresh_pending then
        return
      end

      resize_refresh_pending = true
      vim.schedule(function()
        resize_refresh_pending = false
        terminal.refresh_current_layout()
      end)
    end,
  })
end
return focus
