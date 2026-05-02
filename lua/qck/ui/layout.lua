local layout = {}

local TABBAR_WIDTH = 6
local WINDOW_GAP_WIDTH = 2
local HORIZONTAL_MARGIN = 0
local VERTICAL_MARGIN = 0
local FLOAT_BORDER_FOOTPRINT = 2

---@return integer
function layout.get_tabbar_width()
  return TABBAR_WIDTH
end

---@return integer
function layout.get_window_gap_width()
  return WINDOW_GAP_WIDTH
end

---@return integer
function layout.get_horizontal_margin()
  return HORIZONTAL_MARGIN
end

---@return integer
function layout.get_vertical_margin()
  return VERTICAL_MARGIN
end

---@return integer
function layout.get_float_border_footprint()
  return FLOAT_BORDER_FOOTPRINT
end

---@return integer
function layout.get_total_width()
  local editor_width = math.max(1, vim.o.columns)
  local min_width = TABBAR_WIDTH + WINDOW_GAP_WIDTH + 1
  return math.max(min_width, editor_width - (HORIZONTAL_MARGIN * 2 + FLOAT_BORDER_FOOTPRINT))
end

---@return integer
function layout.get_total_height()
  local editor_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  return math.max(1, editor_height - (VERTICAL_MARGIN * 2 + FLOAT_BORDER_FOOTPRINT))
end

---@return integer, integer
function layout.get_origin()
  return math.max(0, VERTICAL_MARGIN), math.max(0, HORIZONTAL_MARGIN)
end

---@return integer, integer
function layout.get_content_size()
  local total_width = layout.get_total_width()
  local total_height = layout.get_total_height()
  return math.max(1, total_width - TABBAR_WIDTH - WINDOW_GAP_WIDTH), total_height
end

---@param term_cfg vim.api.keyset.win_config|nil
---@return vim.api.keyset.win_config
local function build_content_float_config(term_cfg)
  term_cfg = vim.tbl_extend("force", term_cfg or {}, {})
  local row, base_col = layout.get_origin()
  local terminal_width, total_height = layout.get_content_size()

  term_cfg.relative = "editor"
  term_cfg.row = row
  term_cfg.col = base_col + TABBAR_WIDTH + WINDOW_GAP_WIDTH
  term_cfg.width = terminal_width
  term_cfg.height = total_height

  return term_cfg
end

---@return vim.api.keyset.win_config
function layout.build_initial_terminal_config()
  return build_content_float_config({
    relative = "editor",
    border = "single",
  })
end

---@param term_win integer
---@return { terminal: vim.api.keyset.win_config, tabbar: vim.api.keyset.win_config }|nil
function layout.build_shared_float_configs(term_win)
  if type(term_win) ~= "number" or not vim.api.nvim_win_is_valid(term_win) then
    return nil
  end

  local row, base_col = layout.get_origin()
  local total_height = layout.get_total_height()

  return {
    terminal = build_content_float_config(vim.api.nvim_win_get_config(term_win)),
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
