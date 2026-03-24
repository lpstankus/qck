-- Snacks terminal handle creation adapter for the UI-owned runtime.
local layout = require("qck.ui.layout")
local notify = require("qck.shared.notify").notify

local terminal = {}

local snacks = nil
local next_handle_count = 1

---@param handle qck.TerminalHandle|table|nil
---@return nil
local function safe_close_handle(handle)
  if type(handle) ~= "table" then
    return
  end

  if type(handle.close) == "function" then
    pcall(function() handle:close() end)
    return
  end

  if type(handle.win) == "number" and vim.api.nvim_win_is_valid(handle.win) then
    pcall(vim.api.nvim_win_close, handle.win, true)
  end

  if type(handle.buf) == "number" and vim.api.nvim_buf_is_valid(handle.buf) then
    pcall(vim.api.nvim_buf_delete, handle.buf, { force = true })
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

---@param snacks_impl { terminal?: { open?: fun(cmd: qck.Command|nil, opts: table|nil): qck.TerminalHandle|nil } }|nil
---@return nil
function terminal.set_snacks(snacks_impl)
  if snacks_impl ~= nil and type(snacks_impl) ~= "table" then
    snacks = nil
    next_handle_count = 1
    return
  end

  snacks = snacks_impl
  next_handle_count = 1
end

---@return qck.TerminalHandle|nil
function terminal.create_handle()
  if not ensure_snacks() then
    return nil
  end

  local ok_open, handle_or_err = pcall(snacks.terminal.open, nil, {
    interactive = true,
    auto_close = true,
    count = next_handle_count,
    win = vim.tbl_extend("force", layout.build_initial_terminal_config(), {
      position = "float",
    }),
  })
  next_handle_count = next_handle_count + 1

  if not ok_open or not handle_or_err then
    local msg = ok_open and "failed to open terminal"
      or ("failed to open terminal: " .. tostring(handle_or_err))
    notify(msg, vim.log.levels.ERROR)
    return nil
  end

  if type(handle_or_err) ~= "table" then
    safe_close_handle(handle_or_err)
    notify("failed to initialize terminal handle", vim.log.levels.ERROR)
    return nil
  end

  return handle_or_err
end

---@param handle qck.TerminalHandle|table|nil
---@return nil
function terminal.close_handle(handle)
  safe_close_handle(handle)
end

return terminal
