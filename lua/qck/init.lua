---@class qck
local qck = {}
local state = require("qck.state")
local terminal = require("qck.terminal")
local tabbar = require("qck.tabbar")
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

---@param id number
---@return boolean
local function is_valid_id(id)
  return type(id) == "number" and id > 0 and id % 1 == 0
end

---@param opts table|nil
---@return table
local function validate_new_opts(opts)
  if opts == nil then
    return {}
  end

  if type(opts) ~= "table" then
    notify(
      "new(opts): opts must be a table. falling back to default options.",
      vim.log.levels.ERROR
    )
    return {}
  end

  return {}
end

---@param cmd any
---@return string|string[]|nil
local function validate_run_cmd(cmd)
  if type(cmd) == "string" then
    if vim.trim(cmd) == "" then
      notify("run(cmd): cmd must not be empty", vim.log.levels.ERROR)
      return nil
    end
    return cmd
  end

  if type(cmd) == "table" then
    if #cmd == 0 then
      notify("run(cmd): cmd list must not be empty", vim.log.levels.ERROR)
      return nil
    end

    local parsed = {}
    for i, part in ipairs(cmd) do
      if type(part) ~= "string" or vim.trim(part) == "" then
        notify(
          ("run(cmd): cmd[%d] must be a non-empty string"):format(i),
          vim.log.levels.ERROR
        )
        return nil
      end
      parsed[i] = part
    end
    return parsed
  end

  notify("run(cmd): cmd must be a string or a list of strings", vim.log.levels.ERROR)
  return nil
end

---@param opts any
---@return table|nil
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

  if opts.title ~= nil and type(opts.title) ~= "string" then
    notify("run(cmd, opts): opts.title must be a string", vim.log.levels.ERROR)
    return nil
  end
  parsed.title = opts.title

  return parsed
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
  for lhs, rhs in pairs(mappings) do
    if type(lhs) ~= "string" then
      notify("setup(opts): mapping lhs must be a string", vim.log.levels.ERROR)
    elseif type(rhs) ~= "function" and type(rhs) ~= "string" then
      notify(
        ("setup(opts): map `%s` rhs must be a function or string"):format(lhs),
        vim.log.levels.ERROR
      )
    else
      parsed[lhs] = rhs
    end
  end

  return parsed
end

---@param cmd any
---@param context string
---@return string|string[]|nil
local function parse_builder_cmd(cmd, context)
  if type(cmd) == "string" then
    if vim.trim(cmd) == "" then
      notify(context .. ": cmd must not be empty", vim.log.levels.ERROR)
      return nil
    end
    return cmd
  end

  if type(cmd) ~= "table" then
    notify(context .. ": cmd must be a string or a list of strings", vim.log.levels.ERROR)
    return nil
  end

  if #cmd == 0 then
    notify(context .. ": cmd list must not be empty", vim.log.levels.ERROR)
    return nil
  end

  local parsed = {}
  for i, part in ipairs(cmd) do
    if type(part) ~= "string" or vim.trim(part) == "" then
      notify(
        ("%s: cmd[%d] must be a non-empty string"):format(context, i),
        vim.log.levels.ERROR
      )
      return nil
    end
    parsed[i] = part
  end

  return parsed
end

---@param input any
---@return table<string, table>
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
      local cmd = parse_builder_cmd(builder.cmd, ("setup(opts): builder `%s`"):format(builder_type))
      if cmd then
        local auto_scroll = builder.auto_scroll
        if auto_scroll ~= nil and type(auto_scroll) ~= "boolean" then
          notify(
            ("setup(opts): builder `%s`.auto_scroll must be a boolean"):format(builder_type),
            vim.log.levels.ERROR
          )
          auto_scroll = nil
        end

        local title = builder.title
        if title ~= nil and type(title) ~= "string" then
          notify(
            ("setup(opts): builder `%s`.title must be a string"):format(builder_type),
            vim.log.levels.ERROR
          )
          title = nil
        end

        parsed[normalized_builder_type] = {
          cmd = cmd,
          auto_scroll = auto_scroll,
          title = title,
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

---@param opts any
---@return table|nil
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
---@return table|nil
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
  close_current = function() terminal.hide_current_if_open() end,
  focus_current = focus_current_terminal,
})

---@class qck.SetupOpts
---@field mappings? table<string, string|function> Buffer-local mappings for qck buffers (terminal: normal+terminal modes, tabbar: normal mode).
---@field builders? table<string, { cmd: string|string[], auto_scroll?: boolean, title?: string }> Workspace builder definitions.
---@class qck.RunOpts
---@field id? integer Optional internal terminal id. Must be a positive integer when provided.
---@field title? string Optional reserved field for future tab/title customization.
---@class qck.BuildOpts
---@field force_new? boolean Restart builder instance when already running.
---@field auto_scroll? boolean Override configured auto-scroll behavior for this run.
---@class qck.SetBuilderCmdOpts
---@field temp? boolean Use a temporary in-memory override that is not persisted.

---Configure qck behavior.
---Mappings defined here are active inside qck terminal and tabbar buffers.
---Each configured mapping is applied in both normal (`n`) and terminal (`t`) modes for terminal buffers, and normal mode (`n`) for tabbar buffers.
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

  if not storage.load() then
    notify("failed to load workspace storage", vim.log.levels.ERROR)
  end
end

---Create a new qck terminal using the next available numeric id.
---If another qck terminal window is currently visible, that window is hidden first.
---@param opts? table Optional terminal options (currently reserved/unused).
---@return nil
function qck.new(opts)
  local parsed_opts = validate_new_opts(opts)
  terminal.create(state.next_free_id(), parsed_opts)
end

---Create and start a long-running command terminal.
---Long-running terminals are preserved after command exit for output inspection.
---Tabbar visual labels (`L1`, `T1`, ...) are display-only; APIs still use internal numeric ids.
---@param cmd string|string[] Command to run.
---@param opts? qck.RunOpts Optional options. Supports `id` and reserved `title`.
---@return nil
function qck.run(cmd, opts)
  local parsed_cmd = validate_run_cmd(cmd)
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
  local parsed_builder_type = validate_builder_type(builder_type, "open_builder(builder_type)")
  if not parsed_builder_type then
    return
  end

  builders.open(parsed_builder_type)
end

---Toggle a running builder terminal window by type.
---This does not create a new builder instance.
---@param builder_type string Configured builder type.
---@return nil
function qck.toggle_builder(builder_type)
  local parsed_builder_type = validate_builder_type(builder_type, "toggle_builder(builder_type)")
  if not parsed_builder_type then
    return
  end

  builders.toggle(parsed_builder_type)
end

---Kill a running builder instance by type.
---@param builder_type string Configured builder type.
---@return nil
function qck.kill_builder(builder_type)
  local parsed_builder_type = validate_builder_type(builder_type, "kill_builder(builder_type)")
  if not parsed_builder_type then
    return
  end

  builders.kill(parsed_builder_type)
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

  local parsed_cmd = parse_builder_cmd(cmd, "set_builder_cmd(builder_type, cmd, opts)")
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
---No-op when no live terminals exist.
---@return nil
function qck.cycle_next()
  local target_id = state.get_cycle_id(1)
  if not target_id then return end

  terminal.open(target_id)
end

---Switch to the previous live terminal id (cyclic order).
---No-op when no live terminals exist.
---@return nil
function qck.cycle_prev()
  local target_id = state.get_cycle_id(-1)
  if not target_id then return end

  terminal.open(target_id)
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
