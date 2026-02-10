local state = require("qck.state")

local tabbar = {}

local TABBAR_WIDTH = 6
local ns = vim.api.nvim_create_namespace("qck_tabbar")
local watch_group = vim.api.nvim_create_augroup(
  "qck_tabbar_watch",
  { clear = true }
)
vim.api.nvim_set_hl(0, "QckTabbarCurrent", { reverse = true, default = true })

local bufnr = nil
local winid = nil
local watched_term_win = nil
local render_rows = {}
local user_mappings = {}
local mapping_lhs = {}
local previous_mapping_lhs = {}
local center_text
local actions = {
  open = function(_) end,
  delete = function(_) end,
  focus_current = function() end,
}

---@param buf integer|nil
---@return boolean
local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf) or false
end


---@param win integer|nil
---@return boolean
local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win) or false
end

---@param rec table|nil
---@return integer|nil
local function get_terminal_window_id(rec)
  if not rec or not rec.win then
    return nil
  end

  if type(rec.win.win) == "number" and
      vim.api.nvim_win_is_valid(rec.win.win)
  then
    return rec.win.win
  end

  if type(rec.win.win) == "function" then
    local ok, win = pcall(function() return rec.win:win() end)
    if ok and type(win) == "number" and vim.api.nvim_win_is_valid(win) then
      return win
    end
  end

  return nil
end

---@return integer|nil
local function get_selected_terminal_id()
  if not winid or not is_valid_win(winid) then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(winid)[1]
  if line < 1 or line > #render_rows then
    return nil
  end

  local row = render_rows[line]
  if not row or not row.selectable then
    return nil
  end

  return row.internal_id
end

---@param line integer
---@return boolean
local function is_selectable_line(line)
  local row = render_rows[line]
  return row and row.selectable or false
end

---@param line integer
---@return integer
local function get_line_cursor_col(line)
  local row = render_rows[line]
  if not row then
    return 0
  end

  local width = 1
  if winid and is_valid_win(winid) then
    width = math.max(1, vim.api.nvim_win_get_width(winid))
  end

  local centered = center_text(row.visual_label, width)
  local first_digit = centered:find("%d")
  if first_digit then
    return first_digit - 1
  end

  local first_non_space = centered:find("%S")
  if first_non_space then
    return first_non_space - 1
  end

  return 0
end

---@param delta integer
local function move_selection(delta)
  if not winid or not is_valid_win(winid) then
    return
  end

  local total = #render_rows
  if total == 0 then
    return
  end

  local line = vim.api.nvim_win_get_cursor(winid)[1]
  local next_line = line

  for _ = 1, total do
    next_line = next_line + delta
    if next_line < 1 then
      next_line = total
    elseif next_line > total then
      next_line = 1
    end

    if is_selectable_line(next_line) then
      break
    end
  end

  vim.api.nvim_win_set_cursor(winid, { next_line, get_line_cursor_col(next_line) })
end

---@param buf integer
local function set_buffer_mappings(buf)
  vim.keymap.set(
    "n",
    "j",
    function() move_selection(1) end,
    { buffer = buf, noremap = true, silent = true }
  )

  vim.keymap.set(
    "n",
    "k",
    function() move_selection(-1) end,
    { buffer = buf, noremap = true, silent = true }
  )

  vim.keymap.set(
    "n",
    "<CR>",
    function()
      local id = get_selected_terminal_id()
      if not id then return end
      actions.open(id)
      actions.focus_current()
    end,
    { buffer = buf, noremap = true, silent = true }
  )

  vim.keymap.set(
    "n",
    "dd",
    function()
      local id = get_selected_terminal_id()
      if not id then return end
      actions.delete(id)
      actions.focus_current()
    end,
    { buffer = buf, noremap = true, silent = true }
  )
end

---@param buf integer
local function apply_user_mappings_to_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lhs_to_clear = {}
  for _, lhs in ipairs(previous_mapping_lhs) do
    lhs_to_clear[lhs] = true
  end
  for _, lhs in ipairs(mapping_lhs) do
    lhs_to_clear[lhs] = true
  end

  for lhs in pairs(lhs_to_clear) do
    pcall(vim.keymap.del, "n", lhs, { buffer = buf })
  end

  for lhs, rhs in pairs(user_mappings) do
    vim.keymap.set("n", lhs, rhs, {
      buffer = buf,
      noremap = true,
      silent = true,
    })
  end
end

---@param buf integer
local function configure_buffer_options(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].filetype = "qck-tabbar"
end

---@return integer
local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  configure_buffer_options(buf)
  set_buffer_mappings(buf)
  apply_user_mappings_to_buf(buf)
  return buf
end

---@return integer
local function ensure_buffer()
  if bufnr and is_valid_buf(bufnr) then
    return bufnr
  end

  bufnr = create_buffer()
  return bufnr
end

---@param win integer
local function apply_window_opts(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false
  vim.wo[win].winfixwidth = true
end

---@param text string
---@param width integer
---@return string
center_text = function(text, width)
  local text_width = vim.fn.strdisplaywidth(text)
  if text_width >= width then
    return text
  end

  local left = math.floor((width - text_width) / 2)
  local right = width - text_width - left
  return string.rep(" ", left) .. text .. string.rep(" ", right)
end

---@class qck.TabbarRow
---@field internal_id integer|nil
---@field visual_label string
---@field kind string
---@field selectable boolean

---@return qck.TabbarRow[]
local function build_render_rows()
  local _, long_running_ids, default_ids = state.partitioned_ids()
  local rows = {}

  for i, id in ipairs(long_running_ids) do
    rows[#rows + 1] = {
      internal_id = id,
      visual_label = ("L%d"):format(i),
      kind = "long_running",
      selectable = true,
    }
  end

  if #long_running_ids > 0 and #default_ids > 0 then
    rows[#rows + 1] = {
      internal_id = nil,
      visual_label = "---",
      kind = "separator",
      selectable = false,
    }
  end

  for i, id in ipairs(default_ids) do
    rows[#rows + 1] = {
      internal_id = id,
      visual_label = ("T%d"):format(i),
      kind = "default",
      selectable = true,
    }
  end

  return rows
end

---@param rows qck.TabbarRow[]
---@param current_id integer|nil
---@param width integer
---@return string[], integer|nil
local function build_tabbar_lines(rows, current_id, width)
  local lines = {}
  local current_idx = nil

  for i, row in ipairs(rows) do
    lines[i] = center_text(row.visual_label, width)
    if row.internal_id == current_id then
      current_idx = i
    end
  end

  return lines, current_idx
end

---@param buf integer
---@param lines string[]
---@param current_idx integer|nil
local function update_tabbar_buffer(buf, lines, current_idx)
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if current_idx then
    vim.api.nvim_buf_set_extmark(buf, ns, current_idx - 1, 0, {
      end_row = current_idx,
      hl_group = "QckTabbarCurrent",
      hl_eol = true,
    })
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

---@param previous_line integer
---@param line_count integer
---@param current_idx integer|nil
local function restore_cursor_position(previous_line, line_count, current_idx)
  if not winid or line_count == 0 then
    return
  end

  local target_line = previous_line
  if target_line < 1 or target_line > line_count then
    target_line = current_idx or 1
  end

  if not is_selectable_line(target_line) then
    for i = 1, line_count do
      if is_selectable_line(i) then
        target_line = i
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(winid, { target_line, get_line_cursor_col(target_line) })
end

---@param term_win integer
local function watch_terminal_win(term_win)
  if watched_term_win == term_win then
    return
  end

  vim.api.nvim_clear_autocmds({ group = watch_group })
  watched_term_win = term_win

  vim.api.nvim_create_autocmd("WinClosed", {
    group = watch_group,
    pattern = tostring(term_win),
    callback = function()
      tabbar.hide()
    end,
    once = true,
  })
end

---@return nil
function tabbar.hide()
  if is_valid_win(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
  winid = nil
  render_rows = {}
  watched_term_win = nil
  vim.api.nvim_clear_autocmds({ group = watch_group })
end

---@param fns table|nil
---@return nil
function tabbar.set_actions(fns)
  if type(fns) ~= "table" then
    return
  end
  if type(fns.open) == "function" then
    actions.open = fns.open
  end
  if type(fns.delete) == "function" then
    actions.delete = fns.delete
  end
  if type(fns.focus_current) == "function" then
    actions.focus_current = fns.focus_current
  end
end

---@param mappings table|nil
---@return nil
function tabbar.set_user_mappings(mappings)
  previous_mapping_lhs = mapping_lhs
  user_mappings = mappings or {}
  mapping_lhs = {}

  for lhs in pairs(user_mappings) do
    mapping_lhs[#mapping_lhs + 1] = lhs
  end

  table.sort(mapping_lhs)
end

---@return nil
function tabbar.apply_user_mappings()
  if not bufnr or not is_valid_buf(bufnr) then
    return
  end

  apply_user_mappings_to_buf(bufnr)
end

---@return integer|nil
function tabbar.get_winid()
  if not is_valid_win(winid) then
    return nil
  end
  return winid
end

---@return boolean
function tabbar.is_focused()
  local tab_win = tabbar.get_winid()
  if not tab_win then
    return false
  end
  return vim.api.nvim_get_current_win() == tab_win
end

---@param current_id integer|nil
---@return nil
function tabbar.render(current_id)
  if not winid or not is_valid_win(winid) then
    return
  end

  local rows = build_render_rows()
  if #rows == 0 then
    tabbar.hide()
    return
  end
  render_rows = rows

  local buf = ensure_buffer()
  local width = math.max(1, vim.api.nvim_win_get_width(winid))
  local previous_line = vim.api.nvim_win_get_cursor(winid)[1]
  local lines, current_idx = build_tabbar_lines(rows, current_id, width)

  update_tabbar_buffer(buf, lines, current_idx)
  restore_cursor_position(previous_line, #lines, current_idx)
end

---@param term_win integer
---@return table
local function build_tabbar_window_config(term_win)
  local cfg = vim.api.nvim_win_get_config(term_win)
  local term_row = math.floor(tonumber(cfg.row) or 0)
  local term_col = math.floor(tonumber(cfg.col) or 0)
  local term_height = vim.api.nvim_win_get_height(term_win)

  return {
    relative = "editor",
    row = term_row,
    col = math.max(0, term_col - TABBAR_WIDTH - 2),
    width = TABBAR_WIDTH,
    height = term_height,
    style = "minimal",
    border = "single",
    focusable = true,
  }
end

---@param buf integer
---@param conf table
---@return nil
local function ensure_tabbar_window(buf, conf)
  if winid and is_valid_win(winid) then
    vim.api.nvim_win_set_buf(winid, buf)
    vim.api.nvim_win_set_config(winid, conf)
    return
  end

  conf.noautocmd = true
  winid = vim.api.nvim_open_win(buf, false, conf)
end

---@param rec table|nil
---@param current_id integer|nil
---@return nil
function tabbar.show_for_terminal(rec, current_id)
  if not state.is_window_open(rec) then
    tabbar.hide()
    return
  end

  local term_win = get_terminal_window_id(rec)
  if not term_win then
    tabbar.hide()
    return
  end
  watch_terminal_win(term_win)

  local conf = build_tabbar_window_config(term_win)
  local buf = ensure_buffer()

  ensure_tabbar_window(buf, conf)
  if not winid then return end

  apply_window_opts(winid)
  tabbar.render(current_id)
end

---@param rec table|nil
---@param current_id integer|nil
---@return nil
function tabbar.sync(rec, current_id)
  if not rec then
    tabbar.hide()
    return
  end

  local ids = state.ordered_ids()
  if #ids == 0 then
    tabbar.hide()
    return
  end

  tabbar.show_for_terminal(rec, current_id)
end

return tabbar
