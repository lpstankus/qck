local layout = require("qck.ui.layout")
local ui = require("qck.ui")
local ui_state = require("qck.ui.state")
local storage = require("qck.tasks.storage")
local terminal_service = require("qck.app.terminal.service")
local notify = require("qck.shared.notify").notify

local terminal = {}

local UI_TERMINAL_CATEGORY_KEY = "terminal"
local UI_AGENT_CATEGORY_KEY = "agent"
local UI_TASK_CATEGORY_KEY = "task"
local UI_TASK_CATEGORY = {
  key = UI_TASK_CATEGORY_KEY,
  label = "R",
}
local UI_AGENT_CATEGORY = {
  key = UI_AGENT_CATEGORY_KEY,
  label = "A",
}

---@param mode string|nil
---@return boolean
local function is_normal_mode(mode)
  return type(mode) == "string" and mode:sub(1, 1) == "n"
end

---@return "normal"|nil
local function capture_mode_intent()
  local ok, mode_info = pcall(vim.api.nvim_get_mode)
  if not ok or type(mode_info) ~= "table" then
    return nil
  end

  return is_normal_mode(mode_info.mode) and "normal" or nil
end

---@param handle any
---@return integer|nil
local function get_window_id(handle)
  if type(handle) ~= "table" then
    return nil
  end

  if type(handle.win) == "number" and vim.api.nvim_win_is_valid(handle.win) then
    return handle.win
  end

  if type(handle.win) == "function" then
    local ok, winid = pcall(function() return handle:win() end)
    if ok and type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
      return winid
    end
  end

  return nil
end

---@param handle any
---@param mode_intent "normal"|nil
---@return nil
local function restore_mode_intent(handle, mode_intent)
  if mode_intent ~= "normal" then
    return
  end

  local winid = get_window_id(handle)
  if not winid then
    return
  end

  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.cmd, "stopinsert")
end

---@param handle any
---@return nil
local function focus_terminal(handle)
  local winid = get_window_id(handle)
  if not winid then
    return
  end

  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.cmd, "startinsert")
end

---@param handle any
---@return boolean
local function is_valid_handle(handle)
  if type(handle) ~= "table" or type(handle.buf_valid) ~= "function" then
    return false
  end

  local ok, valid = pcall(function() return handle:buf_valid() end)
  return ok and valid == true
end

---@param workspace string
---@param name string
---@return string
local function task_identity_key(workspace, name)
  return workspace .. "\n" .. name
end

---@param workspace string
---@return string
local function agent_identity_key(workspace)
  return workspace
end

---@param key string
---@return qck.UiTabRecord|nil
local function find_task_tab_by_key(key)
  for _, tab_id in ipairs(ui_state.traversal_ids()) do
    local tab = ui_state.get_tab(tab_id)
    local handle = tab and tab.terminal or nil
    if tab
      and tab.category_key == UI_TASK_CATEGORY_KEY
      and type(handle) == "table"
      and handle.qck_task_key == key
      and is_valid_handle(handle)
    then
      return tab
    end
  end

  return nil
end

---@param key string
---@return qck.UiTabRecord|nil
local function find_agent_tab_by_key(key)
  for _, tab_id in ipairs(ui_state.traversal_ids()) do
    local tab = ui_state.get_tab(tab_id)
    local handle = tab and tab.terminal or nil
    if tab
      and tab.category_key == UI_AGENT_CATEGORY_KEY
      and type(handle) == "table"
      and handle.qck_agent_key == key
      and is_valid_handle(handle)
    then
      return tab
    end
  end

  return nil
end

---@param tab qck.UiTabRecord|nil
---@param workspace string
---@param name string
---@return boolean
local function update_task_tab_identity(tab, workspace, name)
  local handle = tab and tab.terminal or nil
  if not tab or type(handle) ~= "table" then
    return false
  end

  handle.qck_task_key = task_identity_key(workspace, name)
  handle.qck_task_workspace = workspace
  handle.qck_task_name = name

  local updated = true
  local entry = storage.get_task_entry(workspace, name)
  if entry and tab.category_display_id ~= entry.order then
    local ok_update = select(1, ui_state.set_tab_display_id(tab.id, entry.order))
    updated = ok_update or updated
  end
  return updated
end

---@param tab qck.UiTabRecord
---@return qck.UiTabRecord|nil
local function show_existing_task_tab(tab)
  return ui.with_suppressed_focus_leave(function()
    local ok, err = ui.set_active_tab(tab.id)
    if not ok then
      notify(err or "failed to select task terminal", vim.log.levels.ERROR)
      return nil
    end

    if not ui.is_visible() then
      ui.show()
    end

    local selected = ui_state.get_tab(tab.id)
    if selected then
      focus_terminal(selected.terminal)
    end
    return selected
  end)
end

---@param tab qck.UiTabRecord
---@return qck.UiTabRecord|nil
local function show_existing_agent_tab(tab)
  return ui.with_suppressed_focus_leave(function()
    local ok, err = ui.set_active_tab(tab.id)
    if not ok then
      notify(err or "failed to select agent terminal", vim.log.levels.ERROR)
      return nil
    end

    if not ui.is_visible() then
      ui.show()
    end

    local selected = ui_state.get_tab(tab.id)
    if selected then
      focus_terminal(selected.terminal)
    end
    return selected
  end)
end

---@param cmd qck.Command|nil
---@param category_key qck.UiCategoryKey
---@param auto_close boolean
---@param preserve_mode boolean|nil
---@param focus_after_attach boolean|nil
---@param attach_opts? qck.UiRegisterTabOpts
---@param opts? { terminal: table|nil, win: table|nil, configure_handle: fun(handle: any)|nil }
---@return qck.UiTabRecord|nil
local function create_and_attach_command(cmd, category_key, auto_close, preserve_mode, focus_after_attach, attach_opts, opts)
  return ui.with_suppressed_focus_leave(function()
    local mode_intent = preserve_mode == true and capture_mode_intent() or nil
    local win_opts = vim.tbl_extend("force", layout.build_initial_terminal_config(), {
      position = "float",
    }, opts and opts.win or {})
    local terminal_opts = vim.tbl_extend("force", opts and opts.terminal or {}, {
      interactive = true,
      auto_close = auto_close,
      win = win_opts,
    })
    local handle = terminal_service.create_handle(cmd, terminal_opts)
    if not handle then
      return nil
    end

    if opts and type(opts.configure_handle) == "function" then
      opts.configure_handle(handle)
    end

    local tab_id, err = ui.attach_and_show(category_key, handle, attach_opts)
    if not tab_id then
      terminal_service.close_handle(handle)
      notify(err or "failed to attach terminal to ui", vim.log.levels.ERROR)
      return nil
    end

    restore_mode_intent(handle, mode_intent)
    if focus_after_attach == true then
      focus_terminal(handle)
    end
    return ui_state.get_tab(tab_id)
  end)
end

---@param preserve_mode boolean|nil
---@return qck.UiTabRecord|nil
function terminal.create_and_attach(preserve_mode)
  return create_and_attach_command(nil, UI_TERMINAL_CATEGORY_KEY, true, preserve_mode, false)
end

---@param task table
---@return qck.UiTabRecord|nil
function terminal.create_task_and_attach(task)
  if type(task) ~= "table" or type(task.workspace) ~= "string" or type(task.name) ~= "string" then
    notify("invalid task terminal request", vim.log.levels.ERROR)
    return nil
  end

  local ok, err = ui.register_category(UI_TASK_CATEGORY)
  if not ok then
    notify(err or "failed to register task terminal category", vim.log.levels.ERROR)
    return nil
  end

  local key = task_identity_key(task.workspace, task.name)
  local existing = find_task_tab_by_key(key)
  if existing then
    return show_existing_task_tab(existing)
  end

  local tab = create_and_attach_command(task.cmd, UI_TASK_CATEGORY.key, false, false, true, {
    display_id = task.order,
  })
  if tab and type(tab.terminal) == "table" then
    tab.terminal.qck_task_key = key
    tab.terminal.qck_task_workspace = task.workspace
    tab.terminal.qck_task_name = task.name
  end
  return tab
end

---@param agent table
---@return qck.UiTabRecord|nil
function terminal.create_agent_and_attach(agent)
  if type(agent) ~= "table" or type(agent.workspace) ~= "string" then
    notify("invalid agent terminal request", vim.log.levels.ERROR)
    return nil
  end

  local ok, err = ui.register_category(UI_AGENT_CATEGORY)
  if not ok then
    notify(err or "failed to register agent terminal category", vim.log.levels.ERROR)
    return nil
  end

  local key = agent_identity_key(agent.workspace)
  local existing = find_agent_tab_by_key(key)
  if existing then
    return show_existing_agent_tab(existing)
  end

  local tab = create_and_attach_command(agent.cmd, UI_AGENT_CATEGORY.key, true, false, true, nil, {
    configure_handle = function(handle)
      handle.qck_agent_key = key
      handle.qck_agent_workspace = agent.workspace
    end,
    win = {
      on_close = function(handle)
        vim.schedule(function()
          if type(handle.buf_valid) == "function" and handle:buf_valid() then
            return
          end

          ui.detach_closed_agent_handle(handle)
        end)
      end,
    },
  })
  if tab and type(tab.terminal) == "table" then
    tab.terminal.qck_agent_key = key
    tab.terminal.qck_agent_workspace = agent.workspace
    local handle = tab.terminal
    vim.schedule(function()
      if type(handle) == "table"
        and type(handle.buf_valid) == "function"
        and not handle:buf_valid()
      then
        ui.detach_closed_agent_handle(handle)
      end
    end)
  end
  return tab
end

---@param workspace string
---@return nil
function terminal.refresh_task_display_ids(workspace)
  if type(workspace) ~= "string" or workspace == "" then
    return
  end

  local updated = false
  for _, tab_id in ipairs(ui_state.traversal_ids()) do
    local tab = ui_state.get_tab(tab_id)
    local handle = tab and tab.terminal or nil
    if tab
      and tab.category_key == UI_TASK_CATEGORY_KEY
      and type(handle) == "table"
      and handle.qck_task_workspace == workspace
      and type(handle.qck_task_name) == "string"
    then
      local entry = storage.get_task_entry(workspace, handle.qck_task_name)
      if entry and tab.category_display_id ~= entry.order then
        local ok_update = select(1, ui_state.set_tab_display_id(tab_id, entry.order))
        updated = ok_update or updated
      end
    end
  end

  if updated then
    require("qck.ui.tabbar").render()
  end
end

---@param workspace string
---@param old_name string
---@param new_name string
---@return nil
function terminal.refresh_renamed_task_identity(workspace, old_name, new_name)
  if type(workspace) ~= "string" or workspace == "" or type(old_name) ~= "string" or type(new_name) ~= "string" then
    return
  end

  local old_key = task_identity_key(workspace, old_name)
  local new_key = task_identity_key(workspace, new_name)
  if old_key == new_key then
    terminal.refresh_task_display_ids(workspace)
    return
  end

  local renamed_tab = find_task_tab_by_key(old_key)
  local target_tab = find_task_tab_by_key(new_key)
  local updated = false

  if target_tab and (not renamed_tab or target_tab.id ~= renamed_tab.id) then
    local ok_delete = select(1, ui.delete_tab(target_tab.id))
    updated = ok_delete or updated
  end

  if renamed_tab then
    updated = update_task_tab_identity(renamed_tab, workspace, new_name) or updated
  end

  terminal.refresh_task_display_ids(workspace)
  if updated then
    require("qck.ui.tabbar").render()
  end
end

---@return nil
function terminal.open_active_or_create()
  if not ui.open_active() then
    terminal.create_and_attach()
  end
end

---@return nil
function terminal.toggle_active_or_create()
  if not ui.toggle_active() then
    terminal.create_and_attach()
  end
end

return terminal
