local keymaps = {}

local notify = require("qck.shared.notify").notify

local DEFAULT_TERMINAL_MODES = { "n", "t" }
local VALID_TERMINAL_MODES = {
  n = true,
  t = true,
}

---@param mode any
---@param lhs string
---@return string[]|nil
local function parse_terminal_modes(mode, lhs)
  if mode == nil then
    return vim.deepcopy(DEFAULT_TERMINAL_MODES)
  end

  local requested_modes = type(mode) == "string" and { mode } or mode
  if type(requested_modes) ~= "table" then
    notify(("setup(opts): map `%s`.mode must be `n`, `t`, or a list of them"):format(lhs), vim.log.levels.ERROR)
    return nil
  end

  if vim.tbl_isempty(requested_modes) then
    notify(("setup(opts): map `%s`.mode list must not be empty"):format(lhs), vim.log.levels.ERROR)
    return nil
  end

  local seen = {}
  for _, value in ipairs(requested_modes) do
    if type(value) ~= "string" or not VALID_TERMINAL_MODES[value] then
      notify(("setup(opts): map `%s`.mode supports only `n` and `t`"):format(lhs), vim.log.levels.ERROR)
      return nil
    end
    seen[value] = true
  end

  local parsed = {}
  for _, value in ipairs(DEFAULT_TERMINAL_MODES) do
    if seen[value] then
      parsed[#parsed + 1] = value
    end
  end

  return parsed
end

---@param raw_mappings table|nil
---@return table
function keymaps.parse(raw_mappings)
  if raw_mappings == nil then
    return {}
  end

  if type(raw_mappings) ~= "table" then
    notify("setup(opts): opts.mappings must be a table", vim.log.levels.ERROR)
    return {}
  end

  local parsed = {}
  for lhs, mapping in pairs(raw_mappings) do
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
        local terminal_modes = parse_terminal_modes(mode, lhs)
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

---@param current_lhs string[]
---@param user_mappings table|nil
---@return string[], table, string[]
function keymaps.update_state(current_lhs, user_mappings)
  local next_lhs = {}

  for lhs in pairs(user_mappings or {}) do
    next_lhs[#next_lhs + 1] = lhs
  end
  table.sort(next_lhs)

  return current_lhs, user_mappings or {}, next_lhs
end

---@param previous_lhs string[]
---@param current_lhs string[]
---@return table<string, boolean>
function keymaps.collect_lhs_to_clear(previous_lhs, current_lhs)
  local lhs_to_clear = {}
  for _, lhs in ipairs(previous_lhs) do
    lhs_to_clear[lhs] = true
  end
  for _, lhs in ipairs(current_lhs) do
    lhs_to_clear[lhs] = true
  end
  return lhs_to_clear
end

---@param buf integer|nil
---@param previous_lhs string[]
---@param current_lhs string[]
---@param user_mappings table|nil
---@param clear_modes string[]
---@param get_modes? fun(mapping: any): string[]
---@return nil
function keymaps.apply_to_buffer(buf, previous_lhs, current_lhs, user_mappings, clear_modes, get_modes)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  for lhs in pairs(keymaps.collect_lhs_to_clear(previous_lhs, current_lhs)) do
    for _, mode in ipairs(clear_modes) do
      pcall(vim.keymap.del, mode, lhs, { buffer = buf })
    end
  end

  for lhs, mapping in pairs(user_mappings or {}) do
    local rhs = type(mapping) == "table" and mapping.rhs or mapping
    local modes = get_modes and get_modes(mapping) or clear_modes

    if type(rhs) == "function" or type(rhs) == "string" then
      for _, mode in ipairs(modes) do
        vim.keymap.set(mode, lhs, rhs, {
          buffer = buf,
          noremap = true,
          silent = true,
        })
      end
    end
  end
end

return keymaps
