local terminal = require("qck.terminal.service")
local tabbar = require("qck.terminal.tabbar")
local storage = require("qck.tasks.storage")
local notify = require("qck.shared.notify").notify

local setup = {}

setup.config = {
  mappings = {},
}

local ok, Snacks = pcall(require, "snacks")
if not ok then error("QCK: snacks.nvim is required") end
terminal.set_snacks(Snacks)
terminal.set_user_mappings({})
tabbar.set_user_mappings({})

local DEFAULT_MAPPING_MODES = { "n", "t" }
local VALID_MAPPING_MODES = {
  n = true,
  t = true,
}

---@param mode any
---@param lhs string
---@return string[]|nil
local function parse_mapping_modes(mode, lhs)
  if mode == nil then
    local default_modes = {}
    for _, value in ipairs(DEFAULT_MAPPING_MODES) do
      default_modes[#default_modes + 1] = value
    end
    return default_modes
  end

  local requested_modes = {}
  if type(mode) == "string" then
    requested_modes[1] = mode
  elseif type(mode) == "table" then
    for _, value in ipairs(mode) do
      requested_modes[#requested_modes + 1] = value
    end
  else
    notify(("setup(opts): map `%s`.mode must be `n`, `t`, or a list of them"):format(lhs), vim.log.levels.ERROR)
    return nil
  end

  if #requested_modes == 0 then
    notify(("setup(opts): map `%s`.mode list must not be empty"):format(lhs), vim.log.levels.ERROR)
    return nil
  end

  local seen_modes = {}
  for _, value in ipairs(requested_modes) do
    if type(value) ~= "string" or not VALID_MAPPING_MODES[value] then
      notify(("setup(opts): map `%s`.mode supports only `n` and `t`"):format(lhs), vim.log.levels.ERROR)
      return nil
    end
    seen_modes[value] = true
  end

  local parsed_modes = {}
  for _, value in ipairs(DEFAULT_MAPPING_MODES) do
    if seen_modes[value] then
      parsed_modes[#parsed_modes + 1] = value
    end
  end

  return parsed_modes
end

local function parse_mappings(mappings)
  if mappings == nil then
    return {}
  end

  if type(mappings) ~= "table" then
    notify("setup(opts): opts.mappings must be a table", vim.log.levels.ERROR)
    return {}
  end

  local parsed = {}
  for lhs, mapping in pairs(mappings) do
    if type(lhs) ~= "string" then
      notify("setup(opts): mapping lhs must be a string", vim.log.levels.ERROR)
    else
      local rhs = mapping
      local mode = nil
      if type(mapping) == "table" then
        rhs = mapping.rhs
        mode = mapping.mode
      end

      if type(rhs) ~= "function" and type(rhs) ~= "string" then
        notify(("setup(opts): map `%s`.rhs must be a function or string"):format(lhs), vim.log.levels.ERROR)
      else
        local terminal_modes = parse_mapping_modes(mode, lhs)
        if terminal_modes then
          parsed[lhs] = {
            rhs = rhs,
            terminal_modes = terminal_modes,
          }
        end
      end
    end
  end

  return parsed
end

---@param mappings table|nil
---@return nil
local function apply_mappings(mappings)
  setup.config.mappings = parse_mappings(mappings)
  terminal.set_user_mappings(setup.config.mappings)
  tabbar.set_user_mappings(setup.config.mappings)
  terminal.apply_user_mappings()
  tabbar.apply_user_mappings()
end

---@param mappings table|nil
---@return boolean
function setup.initialize(mappings)
  apply_mappings(mappings)

  local ok_load, load_err = storage.load()
  if not ok_load then
    notify(("failed to load workspace storage: %s; run qck.clear_storage() to reset persisted workspace data"):format(load_err or "unknown error"), vim.log.levels.WARN)
    return false
  end

  return true
end

setup.parse_mapping_modes = parse_mapping_modes
setup.parse_mappings = parse_mappings

return setup
