local helpers = require("qck.helpers")
local state = require("qck.state")
local tabbar = require("qck.tabbar")

local terminal = {}

local snacks = nil
local user_mappings = {}
local mapping_lhs = {}
local previous_mapping_lhs = {}
local deleting_ids = {}
local mapping_modes = { "n", "t" }

function terminal.set_snacks(snacks_impl)
  snacks = snacks_impl
end

local function terminal_bufnr(rec)
  if not rec or not rec.win then
    return nil
  end

  if type(rec.win.buf) == "number" and vim.api.nvim_buf_is_valid(rec.win.buf) then
    return rec.win.buf
  end

  if type(rec.win.buf) == "function" then
    local ok, bufnr = pcall(function() return rec.win:buf() end)
    if ok and type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
      return bufnr
    end
  end

  return nil
end

local function apply_user_mappings_to_buf(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lhs_to_clear = {}
  for _, lhs in ipairs(previous_mapping_lhs) do
    lhs_to_clear[lhs] = true
  end
  for _, lhs in ipairs(mapping_lhs) do
    lhs_to_clear[lhs] = true
  end

  for lhs in pairs(lhs_to_clear) do
    for _, mode in ipairs(mapping_modes) do
      pcall(vim.keymap.del, mode, lhs, { buffer = bufnr })
    end
  end

  for lhs, rhs in pairs(user_mappings) do
    for _, mode in ipairs(mapping_modes) do
      vim.keymap.set(mode, lhs, rhs, {
        buffer = bufnr,
        noremap = true,
        silent = true,
      })
    end
  end
end

function terminal.set_user_mappings(mappings)
  previous_mapping_lhs = mapping_lhs
  user_mappings = mappings or {}
  mapping_lhs = {}

  for lhs in pairs(user_mappings) do
    mapping_lhs[#mapping_lhs + 1] = lhs
  end

  table.sort(mapping_lhs)
end

function terminal.apply_user_mappings()
  for _, id in ipairs(state.live_ids()) do
    local rec = state.get_terminal(id)
    apply_user_mappings_to_buf(terminal_bufnr(rec))
  end
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

local function close_current_window_before_switch(target_id)
  local current_id = state.get_current_id()
  if not current_id or current_id == target_id then
    return
  end

  hide_window_if_open(current_id)
end

function terminal.get_current_winid()
  local current_id = state.get_current_id()
  if not current_id then
    return nil
  end

  local rec = state.get_terminal(current_id)
  if not helpers.is_window_open(rec) then
    return nil
  end

  if type(rec.win.win) == "number" and vim.api.nvim_win_is_valid(rec.win.win) then
    return rec.win.win
  end

  if type(rec.win.win) == "function" then
    local ok, win = pcall(function() return rec.win:win() end)
    if ok and type(win) == "number" and vim.api.nvim_win_is_valid(win) then
      return win
    end
  end

  return nil
end

function terminal.create(id, opts)
  if not ensure_snacks() then
    return nil
  end
  close_current_window_before_switch(id)

  local rec = {
    win = nil,
    meta = {},
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
  apply_user_mappings_to_buf(terminal_bufnr(rec))
  tabbar.sync(rec, id)

  rec.win:on("BufWipeout", function()
    if deleting_ids[id] then
      return
    end
    if state.get_terminal(id) == rec then
      state.remove_terminal(id)
      state.update_current_after_removal(id)
      sync_tabbar_for_current()
    end
  end, { buf = true })

  return rec
end

function terminal.ensure(id)
  local rec = state.get_terminal(id)
  if helpers.is_valid_record(rec) then
    return rec
  end

  state.remove_terminal(id)
  return terminal.create(id)
end

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

function terminal.delete(id)
  state.prune_stale()

  local rec = state.get_terminal(id)
  if not rec then
    helpers.notify(
      ("terminal %d does not exist (no-op)"):format(id),
      vim.log.levels.WARN
    )
    return
  end

  local ids = state.live_ids()
  local next_id = nil
  for i, live_id in ipairs(ids) do
    if live_id == id and #ids > 1 then
      local next_idx = i < #ids and i + 1 or i - 1
      next_id = ids[next_idx]
      break
    end
  end

  local removed_current = state.get_current_id() == id
  deleting_ids[id] = true
  local ok_close, err = pcall(function() rec.win:close() end)
  deleting_ids[id] = nil
  if not ok_close then
    helpers.notify(
      ("failed to delete terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
    return
  end

  state.remove_terminal(id)

  if not removed_current then
    sync_tabbar_for_current()
    return
  end

  state.set_current_id(nil)
  if next_id then
    terminal.open(next_id)
  else
    tabbar.hide()
  end
end

return terminal
