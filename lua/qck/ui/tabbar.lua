-- UI-owned tabbar presentation and row actions.
--
-- Rendering comes from `qck.ui.state`, and tabbar interactions now route back
-- through `qck.ui` so UI remains the canonical owner of selection, deletion,
-- motion, and focus behavior.
local ui_state = require("qck.ui.state")
local keymaps = require("qck.shared.keymaps")
local layout = require("qck.ui.layout")
local runtime = require("qck.ui.runtime")

local tabbar = {}

local ns = vim.api.nvim_create_namespace("qck_tabbar")
vim.api.nvim_set_hl(0, "QckTabbarCurrent", { reverse = true, default = true })

local render_rows = {}
local user_mappings = {}
local mapping_lhs = {}
local previous_mapping_lhs = {}
local center_text
---@class qck.UiTabbarRow
---@field tab_id qck.UiTabId|nil
---@field visual_label string

---@return qck.ui|nil
local function get_ui()
  local ok, ui = pcall(require, "qck.ui")
  if ok then
    return ui
  end

  return nil
end

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

---@param terminal any
---@return integer|nil
local function get_terminal_window_id(terminal)
  if not terminal then
    return nil
  end

  if type(terminal.win) == "number" and vim.api.nvim_win_is_valid(terminal.win) then
    return terminal.win
  end

  if type(terminal.win) == "function" then
    local ok, win = pcall(function() return terminal:win() end)
    if ok and type(win) == "number" and vim.api.nvim_win_is_valid(win) then
      return win
    end
  end

  return nil
end

---@return qck.UiTabId|nil
local function get_selected_tab_id()
  local winid = runtime.get_tabbar_winid()
  if not winid or not is_valid_win(winid) then
    return nil
  end

  local line = vim.api.nvim_win_get_cursor(winid)[1]
  if line < 1 or line > #render_rows then
    return nil
  end

  local row = render_rows[line]
  return row and row.tab_id or nil
end

---@param winid integer
---@param line integer
---@param screenrow integer|nil
---@return boolean
local function is_mouse_on_line(winid, line, screenrow)
  if not is_valid_win(winid) or type(line) ~= "number" or line < 1 then
    return false
  end

  if type(screenrow) ~= "number" or screenrow < 1 then
    return true
  end

  local pos = vim.fn.screenpos(winid, line, 1)
  return type(pos) == "table" and tonumber(pos.row) == screenrow
end

---@param mouse table|nil
---@return qck.UiTabId|nil
local function get_mouse_tab_id(mouse)
  local winid = runtime.get_tabbar_winid()
  if not winid or not is_valid_win(winid) then
    return nil
  end

  local mousepos = type(mouse) == "table" and mouse or vim.fn.getmousepos()
  if type(mousepos) ~= "table" then
    return nil
  end

  if type(mousepos.winid) == "number" and mousepos.winid ~= winid then
    return nil
  end

  local line = tonumber(mousepos.line)
  if not line or line < 1 or line > #render_rows then
    return nil
  end

  if not is_mouse_on_line(winid, line, tonumber(mousepos.screenrow)) then
    return nil
  end

  local row = render_rows[line]
  return row and row.tab_id or nil
end

---@return nil
local function focus_visible_terminal()
  local winid = runtime.get_content_winid()
  if not winid or not is_valid_win(winid) then
    return
  end

  pcall(vim.api.nvim_set_current_win, winid)
  pcall(vim.cmd, "startinsert")
end

---@param id qck.UiTabId
---@return integer|nil
local function get_line_for_tab_id(id)
  if type(id) ~= "number" then
    return nil
  end

  for line, row in ipairs(render_rows) do
    if row.tab_id == id then
      return line
    end
  end

  return nil
end

---@param line integer
---@return integer
local function get_line_cursor_col(line)
  local row = render_rows[line]
  if not row then
    return 0
  end

  local width = 1
  local winid = runtime.get_tabbar_winid()
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
  local winid = runtime.get_tabbar_winid()
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

    break
  end

  vim.api.nvim_win_set_cursor(winid, { next_line, get_line_cursor_col(next_line) })
end

---@param delta integer
local function move_selected_tab(delta)
  local tab_id = get_selected_tab_id()
  if not tab_id then
    return
  end

  local ui = get_ui()
  if not ui or type(ui.move_tab) ~= "function" then
    return
  end

  ui.move_tab(tab_id, delta < 0 and -1 or 1)

  local line = get_line_for_tab_id(tab_id)
  if not line then
    return
  end

  local winid = runtime.get_tabbar_winid()
  if not winid or not is_valid_win(winid) then
    return
  end

  vim.api.nvim_win_set_cursor(winid, { line, get_line_cursor_col(line) })
end

---@param buf integer
local function set_buffer_mappings(buf)
  vim.keymap.set("n", "j", function() move_selection(1) end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "k", function() move_selection(-1) end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "J", function() move_selected_tab(1) end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "K", function() move_selected_tab(-1) end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<LeftRelease>", function() tabbar.handle_left_click() end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "<CR>", function()
    local tab_id = get_selected_tab_id()
    local ui = get_ui()
    if not tab_id or not ui then return end
    ui.set_active_tab(tab_id)
    ui.toggle_tabbar_focus()
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "dd", function()
    local tab_id = get_selected_tab_id()
    local ui = get_ui()
    if not tab_id or not ui then return end
    ui.delete_tab(tab_id)
    ui.toggle_tabbar_focus()
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    local ui = get_ui()
    if ui then
      ui.toggle_tabbar_focus()
    end
  end, { buffer = buf, noremap = true, silent = true })
end

---@param buf integer
local function apply_user_mappings_to_buf(buf)
  keymaps.apply_to_buffer(buf, previous_mapping_lhs, mapping_lhs, user_mappings, { "n" })
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
  local bufnr = runtime.get_tabbar_bufnr()
  if bufnr and is_valid_buf(bufnr) then
    return bufnr
  end

  bufnr = create_buffer()
  runtime.set_tabbar_bufnr(bufnr)
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

---@return qck.UiTabbarRow[]
local function build_render_rows()
  local rows = {}

  for _, tab_id in ipairs(ui_state.traversal_ids()) do
    local tab = ui_state.get_tab(tab_id)
    if tab then
      rows[#rows + 1] = {
        tab_id = tab.id,
        visual_label = ("%s%d"):format(tab.category_label, tab.category_display_id),
      }
    end
  end

  return rows
end

---@param rows qck.UiTabbarRow[]
---@param width integer
---@return string[], integer|nil
local function build_tabbar_lines(rows, width)
  local active_tab_id = ui_state.resolve_active_tab()
  local lines = {}
  local current_idx = nil

  for i, row in ipairs(rows) do
    lines[i] = center_text(row.visual_label, width)
    if row.tab_id == active_tab_id then
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
  local winid = runtime.get_tabbar_winid()
  if not winid or line_count == 0 then
    return
  end

  local target_line = previous_line
  if target_line < 1 or target_line > line_count then
    target_line = current_idx or 1
  end

  vim.api.nvim_win_set_cursor(winid, { target_line, get_line_cursor_col(target_line) })
end

---@return nil
function tabbar.hide()
  local winid = runtime.get_tabbar_winid()
  if is_valid_win(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
  runtime.clear_tabbar_winid()
  render_rows = {}
end

---@param mouse table|nil
---@return boolean
function tabbar.handle_left_click(mouse)
  local tab_id = get_mouse_tab_id(mouse)
  local ui = get_ui()
  if not tab_id or not ui then
    return false
  end

  if type(ui.set_active_tab) ~= "function" then
    return false
  end

  local ok = select(1, ui.set_active_tab(tab_id))
  if ok then
    focus_visible_terminal()
  end

  return ok == true
end

---@param raw_mappings table|nil
---@return nil
function tabbar.set_user_mappings(raw_mappings)
  previous_mapping_lhs, user_mappings, mapping_lhs = keymaps.update_state(mapping_lhs, raw_mappings)
end

---@return nil
function tabbar.apply_user_mappings()
  apply_user_mappings_to_buf(runtime.get_tabbar_bufnr())
end

---@return integer|nil
function tabbar.get_winid()
  local winid = runtime.get_tabbar_winid()
  if not is_valid_win(winid) then
    return nil
  end
  return winid
end

---@return nil
function tabbar.render()
  local winid = runtime.get_tabbar_winid()
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
  local lines, current_idx = build_tabbar_lines(rows, width)

  update_tabbar_buffer(buf, lines, current_idx)
  restore_cursor_position(previous_line, #lines, current_idx)
end

---@param term_win integer
---@return table
local function build_tabbar_window_config(term_win)
  local shared_cfg = layout.build_shared_float_configs(term_win)
  return shared_cfg and shared_cfg.tabbar or nil
end

---@param buf integer
---@param conf table
---@return nil
local function ensure_tabbar_window(buf, conf)
  local winid = runtime.get_tabbar_winid()
  if winid and is_valid_win(winid) then
    vim.api.nvim_win_set_buf(winid, buf)
    vim.api.nvim_win_set_config(winid, conf)
    return
  end

  conf.noautocmd = true
  winid = vim.api.nvim_open_win(buf, false, conf)
  runtime.set_tabbar_winid(winid)
end

---@param terminal any
---@return nil
function tabbar.show_for_terminal(terminal)
  local term_win = get_terminal_window_id(terminal)
  if not term_win then
    tabbar.hide()
    return
  end
  local conf = build_tabbar_window_config(term_win)
  if not conf then
    tabbar.hide()
    return
  end
  local buf = ensure_buffer()

  ensure_tabbar_window(buf, conf)
  local winid = runtime.get_tabbar_winid()
  if not winid then return end

  apply_window_opts(winid)
  tabbar.render()
end

return tabbar
