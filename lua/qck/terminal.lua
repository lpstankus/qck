local state = require("qck.state")
local tabbar = require("qck.tabbar")

local terminal = {}

local snacks = nil
local user_mappings = {}
local mapping_lhs = {}
local previous_mapping_lhs = {}
local deleting_ids = {}
local mapping_modes = { "n", "t" }
local buffer_hook_groups = {}

---@param msg string
---@param level integer|nil
---@return nil
local function notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

---@param rec table|nil
---@return table|nil
local function get_terminal_handle(rec)
  if not rec or type(rec) ~= "table" then
    return nil
  end
  if not rec.win then
    return nil
  end
  return rec.win
end

---@param kind string|nil
---@return string
local function normalize_terminal_kind(kind)
  if kind == "long_running" then
    return "long_running"
  end
  return "default"
end

---@param builder_type any
---@return string|nil
local function normalize_builder_type(builder_type)
  if type(builder_type) ~= "string" then
    return nil
  end

  local trimmed = vim.trim(builder_type)
  if trimmed == "" then
    return nil
  end

  return trimmed
end

---@param snacks_impl table|nil
---@return nil
function terminal.set_snacks(snacks_impl)
  if snacks_impl ~= nil and type(snacks_impl) ~= "table" then
    snacks = nil
    return
  end
  snacks = snacks_impl
end

---@param rec table|nil
---@return integer|nil
local function terminal_bufnr(rec)
  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    return nil
  end

  if type(rec_win.buf) == "number" and
      vim.api.nvim_buf_is_valid(rec_win.buf)
  then
    return rec_win.buf
  end

  if type(rec_win.buf) == "function" then
    local ok, bufnr = pcall(function() return rec_win:buf() end)
    if ok and type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
      return bufnr
    end
  end

  return nil
end

---@param bufnr integer|nil
---@return nil
local function clear_buffer_hook_group(bufnr)
  if not bufnr then
    return
  end

  local group_id = buffer_hook_groups[bufnr]
  if not group_id then
    return
  end

  pcall(vim.api.nvim_del_augroup_by_id, group_id)
  buffer_hook_groups[bufnr] = nil
end

---@param rec table|nil
---@return nil
local function clear_terminal_buffer_hooks(rec)
  clear_buffer_hook_group(terminal_bufnr(rec))
end

---@param rec table|nil
---@return integer|nil
local function reset_terminal_buffer_hook_group(rec)
  local bufnr = terminal_bufnr(rec)
  if not bufnr then
    return nil
  end

  clear_buffer_hook_group(bufnr)
  local group_id = vim.api.nvim_create_augroup(("qck_terminal_%d"):format(bufnr), { clear = true })
  buffer_hook_groups[bufnr] = group_id
  return group_id
end

---@param id integer
---@param rec table|nil
---@return nil
local function purge_terminal_record(id, rec)
  clear_terminal_buffer_hooks(rec)
  state.remove_terminal(id)
end

---@param id integer
---@param rec table|nil
---@return nil
local function remove_terminal_record(id, rec)
  purge_terminal_record(id, rec)
  state.update_current_after_removal(id)
end

---@param bufnr integer|nil
---@return nil
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

---@param mappings table|nil
---@return nil
function terminal.set_user_mappings(mappings)
  previous_mapping_lhs = mapping_lhs
  user_mappings = mappings or {}
  mapping_lhs = {}

  for lhs in pairs(user_mappings) do
    mapping_lhs[#mapping_lhs + 1] = lhs
  end

  table.sort(mapping_lhs)
end

---@return nil
function terminal.apply_user_mappings()
  for _, id in ipairs(state.live_ids()) do
    local rec = state.get_terminal(id)
    apply_user_mappings_to_buf(terminal_bufnr(rec))
  end
end

---@return boolean
local function ensure_snacks()
  if type(snacks) ~= "table" then
    notify("snacks.nvim is required", vim.log.levels.ERROR)
    return false
  end

  if type(snacks.terminal) ~= "table" then
    notify("snacks.nvim terminal API is unavailable", vim.log.levels.ERROR)
    return false
  end

  if type(snacks.terminal.open) ~= "function" then
    notify("snacks.nvim terminal.open is unavailable", vim.log.levels.ERROR)
    return false
  end

  return true
end

---@return nil
local function sync_tabbar_for_current()
  local current_id = state.get_current_id()
  if not current_id then
    tabbar.hide()
    return
  end

  local current_rec = state.get_terminal(current_id)
  if not state.is_window_open(current_rec) then
    tabbar.hide()
    return
  end

  tabbar.sync(current_rec, current_id)
end

---@param id integer
---@return nil
local function hide_window_if_open(id)
  local rec = state.get_terminal(id)
  if not state.is_window_open(rec) then
    return
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    return
  end

  local ok_hide, err = pcall(function() rec_win:toggle() end)
  if not ok_hide then
    notify(
      ("failed to hide terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
  end
end

---@param target_id integer
---@return nil
local function close_current_window_before_switch(target_id)
  local current_id = state.get_current_id()
  if not current_id or current_id == target_id then
    return
  end

  hide_window_if_open(current_id)
end

---@return integer|nil
function terminal.get_current_winid()
  local current_id = state.get_current_id()
  if not current_id then
    return nil
  end

  local rec = state.get_terminal(current_id)
  if not state.is_window_open(rec) then
    return nil
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    return nil
  end

  if type(rec_win.win) == "number" and
      vim.api.nvim_win_is_valid(rec_win.win)
  then
    return rec_win.win
  end

  if type(rec_win.win) == "function" then
    local ok, win = pcall(function() return rec_win:win() end)
    if ok and type(win) == "number" and vim.api.nvim_win_is_valid(win) then
      return win
    end
  end

  return nil
end

---@param id integer
---@param opts table|nil
---@return table|nil
function terminal.create(id, opts)
  opts = opts or {}
  local kind = normalize_terminal_kind(opts.kind)
  local builder_type = normalize_builder_type(opts.builder_type)
  local cmd = opts.cmd

  if not snacks or not ensure_snacks() then return nil end

  close_current_window_before_switch(id)

  local rec = {
    win = nil,
    meta = {
      kind = kind,
      builder_type = builder_type,
    },
  }

  local term_opts = {
    interactive = true,
    auto_close = kind == "long_running" and false or true,
    count = id,
    win = {
      position = "float",
      relative = "editor",
      border = "single",
      width = 0.8,
      height = 0.8,
    },
  }

  local ok_open, term_or_err = pcall(snacks.terminal.open, cmd, term_opts)
  if not ok_open or not term_or_err then
    local msg = ok_open and "failed to open terminal"
        or ("failed to open terminal: " .. tostring(term_or_err))
    notify(msg, vim.log.levels.ERROR)
    return nil
  end

  rec.win = term_or_err
  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    notify(
      ("failed to initialize terminal %d handle"):format(id),
      vim.log.levels.ERROR
    )
    return nil
  end

  state.set_terminal(id, rec)
  state.set_current_id(id)
  apply_user_mappings_to_buf(terminal_bufnr(rec))
  reset_terminal_buffer_hook_group(rec)
  tabbar.sync(rec, id)

  if type(rec_win.on) == "function" then
    rec_win:on("BufWipeout", function()
      if deleting_ids[id] then
        return
      end
      if state.get_terminal(id) == rec then
        remove_terminal_record(id, rec)
        sync_tabbar_for_current()
      end
    end, { buf = true })
  end

  return rec
end

---@param id integer
---@return table|nil
function terminal.ensure(id)
  local rec = state.get_terminal(id)
  if state.is_valid_record(rec) then
    return rec
  end

  remove_terminal_record(id, rec)
  return terminal.create(id)
end

---@param id integer
---@param cmd string|string[]
---@param opts table|nil
---@return table|nil
function terminal.run(id, cmd, opts)
  state.prune_stale()
  if state.get_terminal(id) then
    notify(
      ("terminal %d already exists; choose a different id"):format(id),
      vim.log.levels.ERROR
    )
    return nil
  end

  local create_opts = {}
  if type(opts) == "table" then
    for k, v in pairs(opts) do
      create_opts[k] = v
    end
  end
  create_opts.kind = "long_running"
  create_opts.cmd = cmd
  return terminal.create(id, create_opts)
end

---@param id integer
---@return table|nil
function terminal.open(id)
  close_current_window_before_switch(id)

  local rec = terminal.ensure(id)
  if not rec then
    return nil
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    remove_terminal_record(id, rec)
    return nil
  end

  if not state.is_window_open(rec) then
    local ok_show, err = pcall(function() rec_win:show() end)
    if not ok_show then
      notify(
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

---@param id integer
---@return nil
function terminal.close_if_open(id)
  state.prune_stale()

  local rec = state.get_terminal(id)
  if not rec then
    notify(
      ("terminal %d does not exist (no-op)"):format(id),
      vim.log.levels.WARN
    )
    return
  end

  if not state.is_window_open(rec) then
    notify(
      ("terminal %d window is closed (no-op)"):format(id),
      vim.log.levels.WARN
    )
    return
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    notify(
      ("terminal %d has an invalid handle (no-op)"):format(id),
      vim.log.levels.WARN
    )
    return
  end

  local ok_close, err = pcall(function() rec_win:close() end)
  if not ok_close then
    notify(
      ("failed to close terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
    return
  end

  remove_terminal_record(id, rec)
  sync_tabbar_for_current()
end

---@param id integer
---@return nil
function terminal.toggle(id)
  local rec = terminal.ensure(id)
  if not rec then
    return
  end

  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    remove_terminal_record(id, rec)
    return
  end

  local ok_toggle, err = pcall(function() rec_win:toggle() end)
  if not ok_toggle then
    notify(
      ("failed to toggle terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
    return
  end

  state.set_current_id(id)
  if state.is_window_open(rec) then
    tabbar.sync(rec, id)
  else
    tabbar.hide()
  end
end

---@return nil
function terminal.hide_current_if_open()
  local current_id = state.get_current_id()
  if not current_id then
    return
  end

  hide_window_if_open(current_id)
end

---@param id integer
---@return nil
function terminal.delete(id)
  state.prune_stale()

  local rec = state.get_terminal(id)
  if not rec then
    notify(
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
  local rec_win = get_terminal_handle(rec)
  if not rec_win then
    purge_terminal_record(id, rec)
    sync_tabbar_for_current()
    return
  end

  deleting_ids[id] = true
  local ok_close, err = pcall(function() rec_win:close() end)
  deleting_ids[id] = nil
  if not ok_close then
    notify(
      ("failed to delete terminal %d: %s"):format(id, tostring(err)),
      vim.log.levels.ERROR
    )
    return
  end

  purge_terminal_record(id, rec)

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
