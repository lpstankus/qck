local layout = {}

local TABBAR_WIDTH = 6
local WINDOW_GAP_WIDTH = 2
local TERMINAL_WIDTH_RATIO = 0.9
local TERMINAL_HEIGHT_RATIO = 0.9

---@return integer
function layout.get_tabbar_width()
  return TABBAR_WIDTH
end

---@return integer
function layout.get_window_gap_width()
  return WINDOW_GAP_WIDTH
end

---@return integer
local function get_total_width()
  local editor_width = math.max(1, vim.o.columns)
  local target_width = math.floor(editor_width * TERMINAL_WIDTH_RATIO)
  return math.min(editor_width, math.max(TABBAR_WIDTH + WINDOW_GAP_WIDTH + 1, target_width))
end

---@return integer
local function get_total_height()
  local editor_height = math.max(1, vim.o.lines)
  local target_height = math.floor(editor_height * TERMINAL_HEIGHT_RATIO)
  return math.min(editor_height, math.max(1, target_height))
end

---@param value any
---@return integer
local function to_int(value)
  return math.floor(tonumber(value) or 0)
end

---@param term_win integer
---@return { terminal: vim.api.keyset.win_config, tabbar: vim.api.keyset.win_config }|nil
function layout.build_shared_float_configs(term_win)
  if type(term_win) ~= "number" or not vim.api.nvim_win_is_valid(term_win) then
    return nil
  end

  local term_cfg = vim.api.nvim_win_get_config(term_win)
  local total_width = get_total_width()
  local total_height = get_total_height()
  local terminal_width = math.max(1, total_width - TABBAR_WIDTH - WINDOW_GAP_WIDTH)
  local base_col = math.max(0, math.floor((vim.o.columns - total_width) / 2))
  local row = to_int(term_cfg.row)

  term_cfg.relative = "editor"
  term_cfg.col = base_col + TABBAR_WIDTH + WINDOW_GAP_WIDTH
  term_cfg.width = terminal_width
  term_cfg.height = total_height

  return {
    terminal = term_cfg,
    tabbar = {
      relative = "editor",
      row = row,
      col = base_col,
      width = TABBAR_WIDTH,
      height = total_height,
      style = "minimal",
      border = "single",
      focusable = true,
    },
  }
end

return layout
