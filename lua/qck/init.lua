---@class qck
local qck = {}
local helpers = require("qck.helpers")
local state = require("qck.state")
local terminal = require("qck.terminal")

local ok, Snacks = pcall(require, "snacks")
if not ok then error("QCK: snacks.nvim is required") end
terminal.set_snacks(Snacks)

---@param opts? qck.Opts
function qck.new(opts)
  local parsed_opts = helpers.validate_opts(opts)
  terminal.create(state.next_free_id(), parsed_opts)
end

function qck.open(id)
  local target_id = nil

  if id ~= nil then
    if not helpers.is_valid_id(id) then
      helpers.notify("id must be a positive integer", vim.log.levels.ERROR)
      return
    end
    target_id = id
  end

  if not target_id and state.get_current_id() then
    target_id = state.get_current_id()
  end

  if not target_id then
    local ids = state.live_ids()
    target_id = ids[1] or state.next_free_id()
  end

  terminal.open(target_id)
end

function qck.close(id)
  local target_id = nil

  if id ~= nil then
    if not helpers.is_valid_id(id) then
      helpers.notify("id must be a positive integer", vim.log.levels.ERROR)
      return
    end
    target_id = id
  end

  if not target_id and state.get_current_id() then
    target_id = state.get_current_id()
  end

  if not target_id then
    helpers.notify("no current terminal selected (no-op)", vim.log.levels.WARN)
    return
  end

  terminal.close_if_open(target_id)
end

function qck.toggle()
  local current_id = state.get_current_id()
  if not current_id then
    local ids = state.live_ids()
    current_id = ids[1]
    state.set_current_id(current_id)
  end

  if not current_id then
    terminal.open(state.next_free_id())
    return
  end

  terminal.toggle(current_id)
end

function qck.cycle_next()
  local target_id = state.get_cycle_id(1)
  if not target_id then return end

  terminal.open(target_id)
end

function qck.cycle_prev()
  local target_id = state.get_cycle_id(-1)
  if not target_id then return end

  terminal.open(target_id)
end

return qck
