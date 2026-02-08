local helpers = require("qck.helpers")
local state = require("qck.state")

local tabbar = {}

local TABBAR_WIDTH = 5
local ns = vim.api.nvim_create_namespace("qck_tabbar")
local watch_group = vim.api.nvim_create_augroup("qck_tabbar_watch", { clear = true })
vim.api.nvim_set_hl(0, "QckTabbarCurrent", { reverse = true, default = true })

local bufnr = nil
local winid = nil
local watched_term_win = nil

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function terminal_winid(rec)
  if not rec or not rec.win then
    return nil
  end

  if type(rec.win.win) == "number" and vim.api.nvim_win_is_valid(rec.win.win) then
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

local function ensure_buf()
  if is_valid_buf(bufnr) then
    return bufnr
  end

  bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
  return bufnr
end

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
---@param width number
---@return string
local function center_text(text, width)
  local text_width = vim.fn.strdisplaywidth(text)
  if text_width >= width then
    return text
  end

  local left = math.floor((width - text_width) / 2)
  local right = width - text_width - left
  return string.rep(" ", left) .. text .. string.rep(" ", right)
end

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

function tabbar.hide()
  if is_valid_win(winid) then
    pcall(vim.api.nvim_win_close, winid, true)
  end
  winid = nil
  watched_term_win = nil
  vim.api.nvim_clear_autocmds({ group = watch_group })
end

function tabbar.render(current_id)
  if not is_valid_win(winid) then
    return
  end

  local ids = state.live_ids()
  if #ids == 0 then
    tabbar.hide()
    return
  end

  local buf = ensure_buf()
  local lines = {}
  local current_idx = nil
  local width = math.max(1, vim.api.nvim_win_get_width(winid))

  for i, id in ipairs(ids) do
    lines[i] = center_text(tostring(id), width)
    if id == current_id then
      current_idx = i
    end
  end

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

function tabbar.show_for_terminal(rec, current_id)
  if not helpers.is_window_open(rec) then
    tabbar.hide()
    return
  end

  local term_win = terminal_winid(rec)
  if not term_win then
    tabbar.hide()
    return
  end
  watch_terminal_win(term_win)

  local cfg = vim.api.nvim_win_get_config(term_win)
  local term_row = math.floor(tonumber(cfg.row) or 0)
  local term_col = math.floor(tonumber(cfg.col) or 0)
  local term_height = vim.api.nvim_win_get_height(term_win)

  local conf = {
    relative = "editor",
    row = term_row,
    col = math.max(0, term_col - TABBAR_WIDTH - 2),
    width = TABBAR_WIDTH,
    height = term_height,
    style = "minimal",
    border = "single",
    focusable = false,
  }

  local buf = ensure_buf()
  if is_valid_win(winid) then
    vim.api.nvim_win_set_buf(winid, buf)
    vim.api.nvim_win_set_config(winid, conf)
  else
    conf.noautocmd = true
    winid = vim.api.nvim_open_win(buf, false, conf)
  end

  apply_window_opts(winid)
  tabbar.render(current_id)
end

function tabbar.sync(rec, current_id)
  if not rec then
    tabbar.hide()
    return
  end

  local ids = state.live_ids()
  if #ids == 0 then
    tabbar.hide()
    return
  end

  tabbar.show_for_terminal(rec, current_id)
end

return tabbar
