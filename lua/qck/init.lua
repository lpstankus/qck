---@class qck
local qck = {}
local helpers = require("qck.helpers")
local state = require("qck.state")
local terminal = require("qck.terminal")
local tabbar = require("qck.tabbar")

local ok, Snacks = pcall(require, "snacks")
if not ok then error("QCK: snacks.nvim is required") end
terminal.set_snacks(Snacks)
terminal.set_user_mappings({})

---@type { mappings: table<string, string|function> }
local config = {
  mappings = {},
}

---@param mappings any
---@return table<string, string|function>
local function parse_mappings(mappings)
  if mappings == nil then
    return {}
  end

  if type(mappings) ~= "table" then
    helpers.notify("setup(opts): opts.mappings must be a table", vim.log.levels.ERROR)
    return {}
  end

  local parsed = {}
  for lhs, rhs in pairs(mappings) do
    if type(lhs) ~= "string" then
      helpers.notify("setup(opts): mapping lhs must be a string", vim.log.levels.ERROR)
    elseif type(rhs) ~= "function" and type(rhs) ~= "string" then
      helpers.notify(
        ("setup(opts): mapping `%s` rhs must be a function or string"):format(lhs),
        vim.log.levels.ERROR
      )
    else
      parsed[lhs] = rhs
    end
  end

  return parsed
end

local function focus_current_terminal()
  local term_win = terminal.get_current_winid()
  if not term_win then
    return
  end
  vim.api.nvim_set_current_win(term_win)
end

tabbar.set_actions({
  open = function(id) terminal.open(id) end,
  delete = function(id) terminal.delete(id) end,
  focus_current = focus_current_terminal,
})

---@param opts? { mappings?: table<string, string|function> }
function qck.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    helpers.notify("setup(opts): opts must be a table", vim.log.levels.ERROR)
    return
  end

  config.mappings = parse_mappings(opts and opts.mappings)
  terminal.set_user_mappings(config.mappings)
  terminal.apply_user_mappings()
end

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

function qck.switch_focus()
  local tab_win = tabbar.get_winid()
  local term_win = terminal.get_current_winid()
  local current_win = vim.api.nvim_get_current_win()

  if tab_win and current_win == tab_win then
    if term_win then
      vim.api.nvim_set_current_win(term_win)
    end
    return
  end

  if term_win and current_win == term_win then
    if tab_win then
      vim.api.nvim_set_current_win(tab_win)
    end
    return
  end

  if term_win then
    vim.api.nvim_set_current_win(term_win)
    return
  end

  if tab_win then
    vim.api.nvim_set_current_win(tab_win)
  end
end

return qck
