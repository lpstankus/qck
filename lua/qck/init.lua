---@class qck
local qck = {}
require("qck.types")
local cmd_util = require("qck.cmd")
local state = require("qck.state")
local terminal = require("qck.terminal")
local tabbar = require("qck.tabbar")
local autocmd = require("qck.autocmd")
local storage = require("qck.storage")
local builders = require("qck.builders")

local ok, Snacks = pcall(require, "snacks")
if not ok then error("QCK: snacks.nvim is required") end
terminal.set_snacks(Snacks)
terminal.set_user_mappings({})
tabbar.set_user_mappings({})

local config = {
  mappings = {},
  builders = {},
}

---@param msg string
---@param level integer|nil
---@return nil
local function notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

local focus_cleanup_in_progress = false

---@param id number
---@return boolean
local function is_valid_id(id)
  return type(id) == "number" and id > 0 and id % 1 == 0
end

---@param opts any
---@return qck.RunOpts|nil
local function validate_run_opts(opts)
  if opts == nil then
    return {}
  end

  if type(opts) ~= "table" then
    notify("run(cmd, opts): opts must be a table", vim.log.levels.ERROR)
    return nil
  end

  local parsed = {}

  if opts.id ~= nil then
    if not is_valid_id(opts.id) then
      notify("run(cmd, opts): opts.id must be a positive integer", vim.log.levels.ERROR)
      return nil
    end
    parsed.id = opts.id
  end

  return parsed
end

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
    notify(
      ("setup(opts): map `%s`.mode must be `n`, `t`, or a list of them"):format(lhs),
      vim.log.levels.ERROR
    )
    return nil
  end

  if #requested_modes == 0 then
    notify(
      ("setup(opts): map `%s`.mode list must not be empty"):format(lhs),
      vim.log.levels.ERROR
    )
    return nil
  end

  local seen_modes = {}
  for _, value in ipairs(requested_modes) do
    if type(value) ~= "string" or not VALID_MAPPING_MODES[value] then
      notify(
        ("setup(opts): map `%s`.mode supports only `n` and `t`"):format(lhs),
        vim.log.levels.ERROR
      )
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
        notify(
          ("setup(opts): map `%s`.rhs must be a function or string"):format(lhs),
          vim.log.levels.ERROR
        )
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

---@param input any
---@return table<string, qck.BuilderDefinition>
local function parse_builders(input)
  if input == nil then
    return {}
  end

  if type(input) ~= "table" then
    notify("setup(opts): opts.builders must be a table", vim.log.levels.ERROR)
    return {}
  end

  local parsed = {}
  for builder_type, builder in pairs(input) do
    local normalized_builder_type = nil
    if type(builder_type) == "string" then
      normalized_builder_type = vim.trim(builder_type)
    end

    if not normalized_builder_type or normalized_builder_type == "" then
      notify("setup(opts): builder type must be a non-empty string", vim.log.levels.ERROR)
    elseif parsed[normalized_builder_type] then
      notify(
        (
          "setup(opts): duplicate builder type `%s` after normalization (original key `%s`)"
        ):format(normalized_builder_type, builder_type),
        vim.log.levels.ERROR
      )
    elseif type(builder) ~= "table" then
      notify(
        ("setup(opts): builder `%s` must be a table"):format(builder_type),
        vim.log.levels.ERROR
      )
    else
      local parsed_cmd = cmd_util.validate(
        builder.cmd,
        ("setup(opts): builder `%s`"):format(builder_type),
        notify
      )
      if parsed_cmd then
        local auto_scroll = builder.auto_scroll
        if auto_scroll ~= nil and type(auto_scroll) ~= "boolean" then
          notify(
            ("setup(opts): builder `%s`.auto_scroll must be a boolean"):format(builder_type),
            vim.log.levels.ERROR
          )
          auto_scroll = nil
        end

        parsed[normalized_builder_type] = {
          cmd = parsed_cmd,
          auto_scroll = auto_scroll,
        }
      end
    end
  end

  return parsed
end

---@param builder_type any
---@param context string
---@return string|nil
local function validate_builder_type(builder_type, context)
  if type(builder_type) ~= "string" or vim.trim(builder_type) == "" then
    notify(context .. ": builder_type must be a non-empty string", vim.log.levels.ERROR)
    return nil
  end

  return vim.trim(builder_type)
end

---@param builder_type any
---@param context string
---@param action fun(parsed_builder_type: string)
---@return nil
local function run_builder_action(builder_type, context, action)
  local parsed_builder_type = validate_builder_type(builder_type, context)
  if not parsed_builder_type then
    return
  end

  action(parsed_builder_type)
end

---@param opts any
---@return qck.BuildOpts|nil
local function validate_build_opts(opts)
  if opts == nil then
    return {}
  end

  if type(opts) ~= "table" then
    notify("build(builder_type, opts): opts must be a table", vim.log.levels.ERROR)
    return nil
  end

  local parsed = {}

  if opts.force_new ~= nil then
    if type(opts.force_new) ~= "boolean" then
      notify("build(builder_type, opts): opts.force_new must be a boolean", vim.log.levels.ERROR)
      return nil
    end
    parsed.force_new = opts.force_new
  end

  if opts.auto_scroll ~= nil then
    if type(opts.auto_scroll) ~= "boolean" then
      notify("build(builder_type, opts): opts.auto_scroll must be a boolean", vim.log.levels.ERROR)
      return nil
    end
    parsed.auto_scroll = opts.auto_scroll
  end

  return parsed
end

---@param opts any
---@return qck.SetBuilderCmdOpts|nil
local function validate_builder_cmd_opts(opts)
  if opts == nil then
    return {}
  end

  if type(opts) ~= "table" then
    notify("set_builder_cmd(builder_type, cmd, opts): opts must be a table", vim.log.levels.ERROR)
    return nil
  end

  local parsed = {}

  if opts.temp ~= nil then
    if type(opts.temp) ~= "boolean" then
      notify("set_builder_cmd(builder_type, cmd, opts): opts.temp must be a boolean", vim.log.levels.ERROR)
      return nil
    end
    parsed.temp = opts.temp
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
  move_up = function(id) terminal.move_up(id) end,
  move_down = function(id) terminal.move_down(id) end,
  close_current = function() terminal.hide_current_if_open() end,
  focus_current = focus_current_terminal,
})

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
    notify(
      ("failed to hide qck terminal after focus left qck windows: %s"):format(tostring(term_err)),
      vim.log.levels.ERROR
    )
  end

  if not ok_tabbar then
    notify(
      ("failed to hide qck tabbar after focus left qck windows: %s"):format(tostring(tabbar_err)),
      vim.log.levels.ERROR
    )
  end
end

autocmd.create({ "WinEnter", "BufEnter", "TabEnter" }, {
  callback = hide_if_focus_left_qck_windows,
})

---@alias qck.MappingMode "n"|"t"
---@class qck.MappingSpec
---@field rhs string|function Mapping rhs.
---@field mode? qck.MappingMode|qck.MappingMode[] Terminal modes to apply (`n`, `t`, or both). Defaults to both when omitted.
---@class qck.SetupOpts
---@field mappings? table<string, string|function|qck.MappingSpec> Buffer-local mappings for qck buffers.
---@field builders? table<string, qck.BuilderDefinition> Workspace builder definitions.
---@class qck.RunOpts
---@field id? integer Optional internal terminal id. Must be a positive integer when provided.
---@class qck.BuildOpts
---@field force_new? boolean Restart builder instance when already running.
---@field auto_scroll? boolean Override configured auto-scroll behavior for this run.
---@class qck.SetBuilderCmdOpts
---@field temp? boolean Use a temporary in-memory override that is not persisted.

---Configure qck behavior.
---Mappings defined here are active inside qck terminal and tabbar buffers.
---For terminal buffers, mappings default to both normal (`n`) and terminal (`t`) modes.
---To scope terminal mapping modes, use `{ rhs = ..., mode = "n" }`, `{ rhs = ..., mode = "t" }`, or `{ rhs = ..., mode = { "n", "t" } }`.
---Tabbar mappings are always applied in normal mode (`n`).
---Calling setup again replaces previously configured qck buffer-local mappings.
---Invalid options are ignored with error notifications.
---@param opts? qck.SetupOpts
---@return nil
function qck.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    notify("setup(opts): opts must be a table", vim.log.levels.ERROR)
    return
  end

  config.mappings = parse_mappings(opts and opts.mappings)
  config.builders = parse_builders(opts and opts.builders)

  builders.set_storage(storage)
  terminal.set_user_mappings(config.mappings)
  tabbar.set_user_mappings(config.mappings)
  builders.set_definitions(config.builders)
  terminal.apply_user_mappings()
  tabbar.apply_user_mappings()

  local ok_load, load_err = storage.load()
  if not ok_load then
    notify(
      ("failed to load workspace storage: %s"):format(load_err or "unknown error"),
      vim.log.levels.ERROR
    )
  end
end

---Create a new qck terminal using the next available numeric id.
---If another qck terminal window is currently visible, that window is hidden first.
---When a qck terminal window is already open, preserves normal mode across the new terminal switch.
---When qck is closed, default terminal-mode entry behavior is preserved.
---@param _opts? table Optional compatibility parameter (currently ignored).
---@return nil
function qck.new(_opts)
  terminal.create(state.next_free_id(), {
    preserve_mode = terminal.get_current_winid() ~= nil,
  })
end

---Create and start a long-running command terminal.
---Long-running terminals are preserved after command exit for output inspection.
---Tabbar visual labels (`L1`, `T1`, ...) are display-only; APIs still use internal numeric ids.
---@param cmd string|string[] Command to run.
---@param opts? qck.RunOpts Optional options. Supports `id`.
---@return nil
function qck.run(cmd, opts)
  local parsed_cmd = cmd_util.validate(cmd, "run(cmd)", notify)
  if not parsed_cmd then
    return
  end

  local parsed_opts = validate_run_opts(opts)
  if not parsed_opts then
    return
  end

  local id = parsed_opts.id or state.next_free_id()
  terminal.run(id, parsed_cmd, parsed_opts)
end

---Build using a configured builder type.
---Only one runtime instance is allowed per builder type.
---If that builder type is already running, this opens the existing instance unless `opts.force_new = true`.
---@param builder_type string Configured builder type.
---@param opts? qck.BuildOpts Optional build options.
---@return nil
function qck.build(builder_type, opts)
  local parsed_builder_type = validate_builder_type(builder_type, "build(builder_type, opts)")
  if not parsed_builder_type then
    return
  end

  local parsed_opts = validate_build_opts(opts)
  if not parsed_opts then
    return
  end

  builders.build(parsed_builder_type, parsed_opts)
end

---Open a running builder terminal by type.
---This does not create a new builder instance.
---@param builder_type string Configured builder type.
---@return nil
function qck.open_builder(builder_type)
  run_builder_action(builder_type, "open_builder(builder_type)", builders.open)
end

---Toggle a running builder terminal window by type.
---This does not create a new builder instance.
---@param builder_type string Configured builder type.
---@return nil
function qck.toggle_builder(builder_type)
  run_builder_action(builder_type, "toggle_builder(builder_type)", builders.toggle)
end

---Kill a running builder instance by type.
---@param builder_type string Configured builder type.
---@return nil
function qck.kill_builder(builder_type)
  run_builder_action(builder_type, "kill_builder(builder_type)", builders.kill)
end

---Override the command for a configured builder type.
---By default the override is persisted for the current workspace.
---When `opts.temp = true`, override is kept in-memory only for this session.
---@param builder_type string Configured builder type.
---@param cmd string|string[] Builder command override.
---@param opts? qck.SetBuilderCmdOpts Optional override behavior.
---@return nil
function qck.set_builder_cmd(builder_type, cmd, opts)
  local parsed_builder_type = validate_builder_type(
    builder_type,
    "set_builder_cmd(builder_type, cmd, opts)"
  )
  if not parsed_builder_type then
    return
  end

  local parsed_cmd = cmd_util.validate(cmd, "set_builder_cmd(builder_type, cmd, opts)", notify)
  if not parsed_cmd then
    return
  end

  local parsed_opts = validate_builder_cmd_opts(opts)
  if not parsed_opts then
    return
  end

  builders.set_builder_cmd(parsed_builder_type, parsed_cmd, parsed_opts)
end

---Reset command override for a configured builder type.
---If a temporary override exists, it is cleared first.
---Otherwise the persisted workspace override is removed.
---@param builder_type string Configured builder type.
---@return nil
function qck.reset_builder_cmd(builder_type)
  local parsed_builder_type = validate_builder_type(builder_type, "reset_builder_cmd(builder_type)")
  if not parsed_builder_type then
    return
  end

  builders.reset_builder_cmd(parsed_builder_type)
end

---Open a terminal by id.
---If the id exists, opens the existing terminal; if it does not exist, creates and opens it.
---When omitted, opens the current terminal, otherwise the first live terminal, or creates a new one.
---When switching ids, the previously current visible terminal window is hidden.
---@param id? number Terminal id to open or create.
---@return nil
function qck.open(id)
  local target_id = nil

  if id ~= nil then
    if not is_valid_id(id) then
      notify("id must be a positive integer", vim.log.levels.ERROR)
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

---Close a terminal window by id only if its window is currently open.
---If the id exists but the window is already closed/hidden, this is a no-op with a warning.
---If `id` is omitted, uses the current terminal id.
---Successful close removes the terminal record from qck state.
---@param id? number Terminal id whose open window should be closed.
---@return nil
function qck.close(id)
  local target_id = nil

  if id ~= nil then
    if not is_valid_id(id) then
      notify("id must be a positive integer", vim.log.levels.ERROR)
      return
    end
    target_id = id
  end

  if not target_id and state.get_current_id() then
    target_id = state.get_current_id()
  end

  if not target_id then
    notify("no current terminal selected (no-op)", vim.log.levels.WARN)
    return
  end

  terminal.close_if_open(target_id)
end

---Toggle visibility of the current terminal.
---If none exists, a new terminal is created and opened.
---If no current id is set but live terminals exist, selects the first live id then toggles it.
---@return nil
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

---Switch to the next live terminal id (cyclic order).
---When cycling from normal mode, the destination terminal stays in normal mode.
---No-op when no live terminals exist.
---@return nil
function qck.cycle_next()
  local target_id = state.get_cycle_id(1)
  if not target_id then return end

  terminal.open(target_id, { preserve_mode = true })
end

---Switch to the previous live terminal id (cyclic order).
---When cycling from normal mode, the destination terminal stays in normal mode.
---No-op when no live terminals exist.
---@return nil
function qck.cycle_prev()
  local target_id = state.get_cycle_id(-1)
  if not target_id then return end

  terminal.open(target_id, { preserve_mode = true })
end

---Toggle focus between the current qck terminal window and the qck tab bar window.
---If only one is available, focus that one; if neither exists, this is a no-op.
---This function does not create/open windows.
---@return nil
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
