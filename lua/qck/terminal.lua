local helpers = require("qck.helpers")
local state = require("qck.state")
local tabbar = require("qck.tabbar")

local terminal = {}

---@type table?
local snacks = nil

---@param snacks_impl table
function terminal.set_snacks(snacks_impl)
  snacks = snacks_impl
end

local function ensure_snacks()
  if snacks then
    return true
  end
  helpers.notify("snacks.nvim is required", vim.log.levels.ERROR)
  return false
end

local function sync_tabbar_for_current()
  local current_id = state.get_current_id()
  if not current_id then
    tabbar.hide()
    return
  end

  local current_rec = state.get_terminal(current_id)
  if not helpers.is_window_open(current_rec) then
    tabbar.hide()
    return
  end

  tabbar.sync(current_rec, current_id)
end

---@param id number
local function hide_window_if_open(id)
  local rec = state.get_terminal(id)
  if not helpers.is_window_open(rec) then
    return
  end

  local ok_hide, err = pcall(function() rec.win:toggle() end)
  if not ok_hide then
    helpers.notify(
      ("failed to hide terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
  end
end

---@param target_id number
local function close_current_window_before_switch(target_id)
  local current_id = state.get_current_id()
  if not current_id or current_id == target_id then
    return
  end

  hide_window_if_open(current_id)
end

---@param id number
---@param opts? qck.Opts
---@return qck.TerminalRecord?
function terminal.create(id, opts)
  if not ensure_snacks() then
    return nil
  end
  close_current_window_before_switch(id)

  local rec = {
    win = nil,
    meta = {
      title = opts and opts.title or nil,
    },
  }

  local term_opts = {
    interactive = true,
    auto_close = true,
    count = id,
    win = {
      position = "float",
      relative = "editor",
      border = "single",
      width = 0.8,
      height = 0.8,
      title = helpers.title_for(id, rec),
      title_pos = "center",
    },
  }

  local ok_open, term_or_err = pcall(snacks.terminal.open, nil, term_opts)
  if not ok_open or not term_or_err then
    local msg = ok_open and "failed to open terminal"
        or ("failed to open terminal: " .. tostring(term_or_err))
    helpers.notify(msg, vim.log.levels.ERROR)
    return nil
  end

  rec.win = term_or_err
  state.set_terminal(id, rec)
  state.set_current_id(id)
  tabbar.sync(rec, id)

  rec.win:on("BufWipeout", function()
    if state.get_terminal(id) == rec then
      state.remove_terminal(id)
      state.update_current_after_removal(id)
      sync_tabbar_for_current()
    end
  end, { buf = true })

  return rec
end

---@param id number
---@return qck.TerminalRecord?
function terminal.ensure(id)
  local rec = state.get_terminal(id)
  if helpers.is_valid_record(rec) then
    return rec
  end

  state.remove_terminal(id)
  return terminal.create(id)
end

---@param id number
---@return qck.TerminalRecord?
function terminal.open(id)
  close_current_window_before_switch(id)

  local rec = terminal.ensure(id)
  if not rec then
    return nil
  end

  if not helpers.is_window_open(rec) then
    local ok_show, err = pcall(function() rec.win:show() end)
    if not ok_show then
      helpers.notify(
        ("failed to open terminal %d: %s"):format(id, tostring(err)),
        vim.log.levels.ERROR
      )
      return nil
    end
  end

  state.set_current_id(id)
  tabbar.sync(rec, id)
  return rec
end

---@param id number
function terminal.close_if_open(id)
  state.prune_stale()

  local rec = state.get_terminal(id)
  if not rec then
    helpers.notify(
      ("terminal %d does not exist (no-op)"):format(id),
      vim.log.levels.WARN
    )
    return
  end

  if not helpers.is_window_open(rec) then
    helpers.notify(
      ("terminal %d window is closed (no-op)"):format(id),
      vim.log.levels.WARN
    )
    return
  end

  local ok_close, err = pcall(function() rec.win:close() end)
  if not ok_close then
    helpers.notify(
      ("failed to close terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
    return
  end

  state.remove_terminal(id)
  state.update_current_after_removal(id)
  sync_tabbar_for_current()
end

---@param id number
function terminal.toggle(id)
  local rec = terminal.ensure(id)
  if not rec then
    return
  end

  local ok_toggle, err = pcall(function() rec.win:toggle() end)
  if not ok_toggle then
    helpers.notify(
      ("failed to toggle terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
    return
  end

  state.set_current_id(id)
  if helpers.is_window_open(rec) then
    tabbar.sync(rec, id)
  else
    tabbar.hide()
  end
end

return terminal
