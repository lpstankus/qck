---@class qck
local qck = {}

local ok, Snacks = pcall(require, "snacks")
if not ok then
  error("QCK: snacks.nvim is required")
end

---@class qck.TerminalMeta
---@field title? string

---@class qck.TerminalRecord
---@field win snacks.win
---@field meta qck.TerminalMeta

---@type table<number, qck.TerminalRecord>
local terminals = {}
local current_id = nil

local function notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

local function is_valid_id(id)
  return type(id) == "number" and id > 0 and id % 1 == 0
end

---@param rec? qck.TerminalRecord
local function is_valid_record(rec)
  return rec and rec.win and rec.win.buf_valid and rec.win:buf_valid()
end

---@param rec? qck.TerminalRecord
local function is_window_open(rec)
  return rec and rec.win and rec.win.valid and rec.win:valid()
end

local function prune_stale()
  for id, rec in pairs(terminals) do
    if not is_valid_record(rec) then
      terminals[id] = nil
    end
  end
  if current_id and not terminals[current_id] then
    current_id = nil
  end
end

---@return number[]
local function live_ids()
  prune_stale()
  local ids = {}
  for id in pairs(terminals) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

local function next_free_id()
  prune_stale()
  local id = 1
  while terminals[id] do
    id = id + 1
  end
  return id
end

---@param opts? table
---@return { title?: string }?
local function normalize_new_opts(opts)
  if opts == nil then
    return {}
  end
  if type(opts) ~= "table" then
    notify("new(opts): opts must be a table", vim.log.levels.ERROR)
    return nil
  end
  local title = opts.title or opts.name
  if title == nil then
    return {}
  end
  if type(title) ~= "string" then
    notify("new(opts): opts.title must be a string", vim.log.levels.ERROR)
    return nil
  end
  title = vim.trim(title)
  if title == "" then
    return {}
  end
  if vim.fn.strchars(title) > 1 then
    notify("new(opts): title must be a single character", vim.log.levels.ERROR)
    return nil
  end
  return { title = title }
end

---@param id number
---@param rec qck.TerminalRecord
local function title_for(id, rec)
  local title = rec.meta and rec.meta.title
  if title and title ~= "" then
    return ("qck [%d] %s"):format(id, title)
  end
  return ("qck [%d]"):format(id)
end

local function update_current_after_removal(removed_id)
  if current_id ~= removed_id then
    return
  end
  local ids = live_ids()
  current_id = ids[1]
end

---@param id number
---@param opts? { title?: string }
---@return qck.TerminalRecord?
local function create_terminal(id, opts)
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
      title = title_for(id, rec),
      title_pos = "center",
    },
  }

  local ok_open, term_or_err = pcall(Snacks.terminal.open, nil, term_opts)
  if not ok_open or not term_or_err then
    local msg = ok_open and "failed to open terminal"
      or ("failed to open terminal: " .. tostring(term_or_err))
    notify(msg, vim.log.levels.ERROR)
    return nil
  end

  rec.win = term_or_err
  terminals[id] = rec
  current_id = id

  rec.win:on("BufWipeout", function()
    if terminals[id] == rec then
      terminals[id] = nil
      update_current_after_removal(id)
    end
  end, { buf = true })

  return rec
end

---@param id number
---@return qck.TerminalRecord?
local function ensure_terminal(id)
  local rec = terminals[id]
  if is_valid_record(rec) then
    return rec
  end
  terminals[id] = nil
  return create_terminal(id)
end

---@param id number
---@return qck.TerminalRecord?
local function open_terminal(id)
  local rec = ensure_terminal(id)
  if not rec then
    return nil
  end

  if not is_window_open(rec) then
    local ok_show, err = pcall(function()
      rec.win:show()
    end)
    if not ok_show then
      notify(("failed to open terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
      return nil
    end
  end

  current_id = id
  return rec
end

---@param id number
local function close_terminal_if_open(id)
  prune_stale()

  local rec = terminals[id]
  if not rec then
    notify(("terminal %d does not exist (no-op)"):format(id), vim.log.levels.WARN)
    return
  end

  if not is_window_open(rec) then
    notify(("terminal %d window is closed (no-op)"):format(id), vim.log.levels.WARN)
    return
  end

  local ok_close, err = pcall(function()
    rec.win:close()
  end)
  if not ok_close then
    notify(("failed to close terminal %d: %s"):format(id, tostring(err)), vim.log.levels.ERROR)
    return
  end

  terminals[id] = nil
  update_current_after_removal(id)
end

---@param direction 1|-1
local function cycle(direction)
  local ids = live_ids()
  if #ids == 0 then
    open_terminal(next_free_id())
    return
  end

  if not current_id or not terminals[current_id] then
    local start_id = direction == 1 and ids[1] or ids[#ids]
    open_terminal(start_id)
    return
  end

  local idx = nil
  for i, id in ipairs(ids) do
    if id == current_id then
      idx = i
      break
    end
  end

  if not idx then
    local start_id = direction == 1 and ids[1] or ids[#ids]
    open_terminal(start_id)
    return
  end

  local next_idx = idx + direction
  if next_idx < 1 then
    next_idx = #ids
  elseif next_idx > #ids then
    next_idx = 1
  end

  open_terminal(ids[next_idx])
end

function qck.new(opts)
  local parsed_opts = normalize_new_opts(opts)
  if not parsed_opts then
    return
  end
  create_terminal(next_free_id(), parsed_opts)
end

function qck.open(id)
  local target_id = nil
  if id ~= nil then
    if not is_valid_id(id) then
      notify("id must be a positive integer", vim.log.levels.ERROR)
      return
    end
    target_id = id
  elseif current_id then
    target_id = current_id
  else
    local ids = live_ids()
    target_id = ids[1] or next_free_id()
  end
  open_terminal(target_id)
end

function qck.close(id)
  local target_id = nil
  if id ~= nil then
    if not is_valid_id(id) then
      notify("id must be a positive integer", vim.log.levels.ERROR)
      return
    end
    target_id = id
  else
    target_id = current_id
  end

  if not target_id then
    notify("no current terminal selected (no-op)", vim.log.levels.WARN)
    return
  end
  close_terminal_if_open(target_id)
end

function qck.toggle()
  if not current_id then
    local ids = live_ids()
    current_id = ids[1]
  end

  if not current_id then
    open_terminal(next_free_id())
    return
  end

  local rec = ensure_terminal(current_id)
  if not rec then
    return
  end

  local ok_toggle, err = pcall(function()
    rec.win:toggle()
  end)
  if not ok_toggle then
    notify(("failed to toggle terminal %d: %s"):format(current_id, tostring(err)), vim.log.levels.ERROR)
  end
end

function qck.cycle_next()
  cycle(1)
end

function qck.cycle_prev()
  cycle(-1)
end

return qck
