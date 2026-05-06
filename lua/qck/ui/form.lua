local autocmd = require("qck.shared.autocmd")

local form = {}

local MIN_SEPARATOR_WIDTH = 2048

---@class qck.FormField
---@field key string
---@field prefix string
---@field value? string

---@class qck.FormOpenOpts
---@field title string
---@field description string
---@field help string
---@field filetype string
---@field fields qck.FormField[]
---@field on_submit fun(values: table<string, string>, controller: qck.FormController): boolean?
---@field on_close? fun()

---@class qck.FormController

local function is_valid_buf(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_win(win)
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function in_insert_mode()
  local mode = vim.api.nvim_get_mode().mode
  return type(mode) == "string" and mode:sub(1, 1) == "i"
end

local function wrapped_field_idx(fields, idx)
  return ((idx - 1) % #fields) + 1
end

local function parse_field_value(state, field_def)
  if not is_valid_buf(state.bufnr) then
    return ""
  end

  local line = vim.api.nvim_buf_get_lines(state.bufnr, field_def.line - 1, field_def.line, false)[1] or ""
  if vim.startswith(line, field_def.prefix) then
    return line:sub(#field_def.prefix + 1)
  end

  local bar_pos = line:find("|", 1, true)
  if bar_pos then
    return line:sub(bar_pos + 1)
  end

  local labeled_value = line:match("^%s*[^:]+:%s*(.*)$")
  if labeled_value ~= nil then
    return labeled_value
  end

  return line
end

local function values(state)
  local out = {}
  for _, field_def in ipairs(state.fields) do
    out[field_def.key] = parse_field_value(state, field_def)
  end
  return out
end

local function separator_for(state, form_values)
  local bar_col = state.fields[1].prefix:find("|", 1, true) or #state.fields[1].prefix
  local max_width = 0
  for _, field_def in ipairs(state.fields) do
    max_width = math.max(max_width, #field_def.prefix + #(form_values[field_def.key] or ""))
  end

  local separator = string.rep("-", math.max(MIN_SEPARATOR_WIDTH, max_width + 64))
  return separator:sub(1, bar_col - 1) .. "+" .. separator:sub(bar_col + 1)
end

local function clamp_cursor_to_field(state)
  if not is_valid_win(state.winid) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  local line = cursor[1]
  local col = cursor[2]
  local target_idx = state.selected_field

  for idx, field_def in ipairs(state.fields) do
    if line == field_def.line then
      target_idx = idx
      break
    end
  end

  state.selected_field = target_idx
  local selected = state.fields[state.selected_field]
  if col < #selected.prefix then
    col = #selected.prefix
  end
  vim.api.nvim_win_set_cursor(state.winid, { selected.line, col })
end

local function sanitize_buffer(state)
  if state.is_sanitizing or not is_valid_buf(state.bufnr) then
    return
  end

  state.is_sanitizing = true
  local form_values = values(state)
  local lines = {
    state.description,
    separator_for(state, form_values),
  }
  for _, field_def in ipairs(state.fields) do
    lines[#lines + 1] = field_def.prefix .. (form_values[field_def.key] or "")
  end
  lines[#lines + 1] = lines[2]
  lines[#lines + 1] = state.help

  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  clamp_cursor_to_field(state)
  state.is_sanitizing = false
end

local function focus_field(state, field_idx)
  if not is_valid_win(state.winid) then
    return
  end

  local was_insert = in_insert_mode()
  sanitize_buffer(state)
  state.selected_field = wrapped_field_idx(state.fields, field_idx)
  local selected = state.fields[state.selected_field]
  vim.api.nvim_win_set_cursor(state.winid, { selected.line, #selected.prefix })
  if was_insert then
    vim.cmd("startinsert!")
  end
end

local function build_window_config(state)
  local width = math.max(50, math.floor(vim.o.columns * 0.5))
  local height = #state.fields + 4
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    focusable = true,
    noautocmd = true,
    title = state.title,
    title_pos = "center",
  }
end

local function set_window_options(state)
  local buf = state.bufnr
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = state.filetype
  if not is_valid_win(state.winid) then
    return
  end
  vim.wo[state.winid].number = false
  vim.wo[state.winid].relativenumber = false
  vim.wo[state.winid].signcolumn = "no"
  vim.wo[state.winid].foldcolumn = "0"
  vim.wo[state.winid].cursorline = false
  vim.wo[state.winid].wrap = false
end

local function apply_keymaps(controller, state)
  local map_opts = { buffer = state.bufnr, noremap = true, silent = true }
  vim.keymap.set({ "n", "i" }, "<Tab>", function() focus_field(state, state.selected_field + 1) end, map_opts)
  vim.keymap.set({ "n", "i" }, "<S-Tab>", function() focus_field(state, state.selected_field - 1) end, map_opts)
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    if state.selected_field == #state.fields then
      controller.submit()
      return
    end
    focus_field(state, state.selected_field + 1)
  end, map_opts)
  vim.keymap.set("n", "<Esc>", function() controller.close() end, map_opts)
end

---@return qck.FormController
function form.create()
  local state = {
    bufnr = nil,
    winid = nil,
    selected_field = 1,
    is_sanitizing = false,
    autocmd_ids = {},
    title = "",
    description = "",
    help = "",
    filetype = "",
    fields = {},
    on_submit = nil,
    on_close = nil,
  }
  local controller = {}

  local function reset_state()
    if type(state.on_close) == "function" then
      state.on_close()
    end
    for _, id in pairs(state.autocmd_ids) do
      autocmd.delete(id)
    end
    state.autocmd_ids = {}
    state.bufnr = nil
    state.winid = nil
    state.selected_field = 1
    state.is_sanitizing = false
    state.title = ""
    state.description = ""
    state.help = ""
    state.filetype = ""
    state.fields = {}
    state.on_submit = nil
    state.on_close = nil
  end

  function controller.close()
    if is_valid_win(state.winid) then
      pcall(vim.api.nvim_win_close, state.winid, true)
    end
    reset_state()
  end

  function controller.submit()
    if not is_valid_win(state.winid) then
      return
    end

    sanitize_buffer(state)
    if type(state.on_submit) == "function" and state.on_submit(values(state), controller) == true then
      controller.close()
    end
  end

  ---@param key_or_idx string|integer
  function controller.focus_field(key_or_idx)
    local idx = key_or_idx
    if type(key_or_idx) == "string" then
      idx = state.selected_field
      for field_idx, field_def in ipairs(state.fields) do
        if field_def.key == key_or_idx then
          idx = field_idx
          break
        end
      end
    end
    focus_field(state, idx)
  end

  function controller.focus_current_field()
    if is_valid_win(state.winid) then
      local line = vim.api.nvim_win_get_cursor(state.winid)[1]
      for field_idx, field_def in ipairs(state.fields) do
        if field_def.line == line then
          state.selected_field = field_idx
          break
        end
      end
    end
    focus_field(state, state.selected_field)
  end

  function controller.get_winid()
    if not is_valid_win(state.winid) then
      return nil
    end
    return state.winid
  end

  ---@param opts qck.FormOpenOpts
  function controller.open(opts)
    if is_valid_win(state.winid) then
      vim.api.nvim_set_current_win(state.winid)
      focus_field(state, state.selected_field)
      return
    end

    state.title = opts.title
    state.description = opts.description
    state.help = opts.help
    state.filetype = opts.filetype
    state.on_submit = opts.on_submit
    state.on_close = opts.on_close
    state.fields = {}
    for idx, field_def in ipairs(opts.fields) do
      state.fields[idx] = {
        key = field_def.key,
        prefix = field_def.prefix,
        value = field_def.value or "",
        line = idx + 2,
      }
    end

    state.bufnr = vim.api.nvim_create_buf(false, true)
    state.winid = vim.api.nvim_open_win(state.bufnr, true, build_window_config(state))
    state.selected_field = 1

    set_window_options(state)
    local lines = {
      state.description,
      "",
    }
    for _, field_def in ipairs(state.fields) do
      lines[#lines + 1] = field_def.prefix .. field_def.value
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = state.help
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
    sanitize_buffer(state)
    apply_keymaps(controller, state)

    state.autocmd_ids.text = autocmd.create({ "TextChanged", "TextChangedI" }, {
      buffer = state.bufnr,
      callback = function() sanitize_buffer(state) end,
    })
    state.autocmd_ids.cursor = autocmd.create({ "CursorMoved", "CursorMovedI", "InsertEnter" }, {
      buffer = state.bufnr,
      callback = function() clamp_cursor_to_field(state) end,
    })
    state.autocmd_ids.wipe = autocmd.create("BufWipeout", {
      buffer = state.bufnr,
      callback = reset_state,
      once = true,
    })

    focus_field(state, 1)
    vim.cmd("startinsert!")
  end

  return controller
end

return form
