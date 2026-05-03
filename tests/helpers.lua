local M = {}

local STORAGE_VERSION = "0.1.0"
local DEFAULT_COLUMNS = vim.o.columns
local DEFAULT_LINES = vim.o.lines
local TEST_DATA_MARKER = "/tests/.tmp/"

local function clear_qck_modules()
  local names = {}
  for name in pairs(package.loaded) do
    if name == "qck" or name:match("^qck%.") then
      names[#names + 1] = name
    end
  end

  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end

  package.loaded.snacks = nil
end

local function reset_windows()
  pcall(vim.cmd, "silent! only")
end

function M.assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(("%s (expected %s, got %s)"):format(msg, tostring(expected), tostring(actual)))
  end
end

function M.assert_truthy(value, msg)
  if not value then
    error(msg)
  end
end

function M.write_storage(data)
  local path = vim.fn.stdpath("data") .. "/qck.json"
  M.assert_truthy(path:find(TEST_DATA_MARKER, 1, true) ~= nil, "test storage must use isolated XDG_DATA_HOME")
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(data) }, path)
end

function M.write_blank_storage()
  M.write_storage({
    version = STORAGE_VERSION,
    workspaces = vim.empty_dict(),
  })
end

function M.reset_environment()
  local ok_mock, mock_snacks = pcall(require, "mock_snacks")
  if ok_mock and type(mock_snacks.reset) == "function" then
    mock_snacks.reset()
  end

  pcall(vim.api.nvim_del_augroup_by_name, "qck")
  vim.o.columns = DEFAULT_COLUMNS
  vim.o.lines = DEFAULT_LINES
  reset_windows()
  vim.wait(20, function() return false end)
  clear_qck_modules()
  M.write_blank_storage()
end

function M.load_qck(opts)
  local mock_snacks = require("mock_snacks")
  mock_snacks.install()

  local qck = require("qck")
  if opts == nil or opts.setup ~= false then
    qck.setup(opts and opts.setup_opts or nil)
  end

  return {
    qck = qck,
    ui = require("qck.ui"),
    ui_state = require("qck.ui.state"),
    storage = require("qck.tasks.storage"),
    task_form = require("qck.tasks.form"),
    task_runner = require("qck.tasks.runner"),
    tabbar = require("qck.ui.tabbar"),
    layout = require("qck.ui.layout"),
    workspace = vim.fn.getcwd(),
  }
end

function M.expected_layout(layout)
  local expected_tabbar_width = layout.get_tabbar_width()
  local expected_gap_width = layout.get_window_gap_width()
  local horizontal_margin = layout.get_horizontal_margin()
  local vertical_margin = layout.get_vertical_margin()
  local border_footprint = 2
  local min_total_width = expected_tabbar_width + expected_gap_width + 1
  local expected_total_width = math.max(
    min_total_width,
    math.min(vim.o.columns, vim.o.columns - (horizontal_margin * 2 + border_footprint))
  )
  local expected_total_height = math.max(
    1,
    math.min(vim.o.lines, vim.o.lines - vim.o.cmdheight - (vertical_margin * 2 + border_footprint))
  )

  return {
    tabbar_width = expected_tabbar_width,
    gap_width = expected_gap_width,
    horizontal_margin = horizontal_margin,
    vertical_margin = vertical_margin,
    total_width = expected_total_width,
    total_height = expected_total_height,
  }
end

function M.assert_window_layout(term_win, tab_win, expected, msg_prefix)
  local term_cfg = vim.api.nvim_win_get_config(term_win)
  local tab_cfg = vim.api.nvim_win_get_config(tab_win)
  local border_footprint = 2
  local term_col = math.floor(tonumber(term_cfg.col) or 0)
  local tab_col = math.floor(tonumber(tab_cfg.col) or 0)
  local term_width = vim.api.nvim_win_get_width(term_win)
  local tab_width = vim.api.nvim_win_get_width(tab_win)
  local term_height = vim.api.nvim_win_get_height(term_win)
  local tab_height = vim.api.nvim_win_get_height(tab_win)
  local expected_base_col = math.max(0, expected.horizontal_margin)
  local expected_base_row = math.max(0, expected.vertical_margin)

  M.assert_eq(tab_width, expected.tabbar_width, msg_prefix .. ": tabbar width should match shared width")
  M.assert_eq(
    term_width,
    expected.total_width - expected.tabbar_width - expected.gap_width,
    msg_prefix .. ": terminal width should shrink by tabbar width and gap"
  )
  M.assert_eq(tab_col, expected_base_col, msg_prefix .. ": tabbar should anchor to the footprint left edge")
  M.assert_eq(
    term_col,
    expected_base_col + expected.tabbar_width + expected.gap_width,
    msg_prefix .. ": terminal should shift right by tabbar width and gap"
  )
  M.assert_eq(
    math.floor(tonumber(tab_cfg.row) or 0),
    expected_base_row,
    msg_prefix .. ": tabbar should anchor to the footprint top edge"
  )
  M.assert_eq(
    math.floor(tonumber(term_cfg.row) or 0),
    expected_base_row,
    msg_prefix .. ": terminal should share the footprint top edge"
  )
  M.assert_eq(
    term_col - (tab_col + tab_width),
    expected.gap_width,
    msg_prefix .. ": tabbar gap should match configured spacing"
  )
  M.assert_eq(
    term_width + tab_width + expected.gap_width,
    expected.total_width,
    msg_prefix .. ": combined width plus gap should match the terminal footprint"
  )
  M.assert_eq(term_height, expected.total_height, msg_prefix .. ": terminal height should match shared height")
  M.assert_eq(tab_height, expected.total_height, msg_prefix .. ": tabbar height should match shared height")
  M.assert_eq(
    vim.o.columns - (tab_col + expected.total_width + border_footprint),
    expected.horizontal_margin,
    msg_prefix .. ": right margin should match configured spacing"
  )
  M.assert_eq(
    vim.o.lines - vim.o.cmdheight - (math.floor(tonumber(tab_cfg.row) or 0) + expected.total_height + border_footprint),
    expected.vertical_margin,
    msg_prefix .. ": bottom margin should match configured spacing"
  )
end

function M.capture_window_layout(term_win, tab_win)
  local term_cfg = vim.api.nvim_win_get_config(term_win)
  local tab_cfg = vim.api.nvim_win_get_config(tab_win)

  return {
    term_row = math.floor(tonumber(term_cfg.row) or 0),
    term_col = math.floor(tonumber(term_cfg.col) or 0),
    term_width = vim.api.nvim_win_get_width(term_win),
    term_height = vim.api.nvim_win_get_height(term_win),
    tab_row = math.floor(tonumber(tab_cfg.row) or 0),
    tab_col = math.floor(tonumber(tab_cfg.col) or 0),
    tab_width = vim.api.nvim_win_get_width(tab_win),
    tab_height = vim.api.nvim_win_get_height(tab_win),
  }
end

function M.assert_layout_snapshot_eq(actual, expected, msg_prefix)
  M.assert_eq(actual.term_row, expected.term_row, msg_prefix .. ": terminal row should stay stable")
  M.assert_eq(actual.term_col, expected.term_col, msg_prefix .. ": terminal col should stay stable")
  M.assert_eq(actual.term_width, expected.term_width, msg_prefix .. ": terminal width should stay stable")
  M.assert_eq(actual.term_height, expected.term_height, msg_prefix .. ": terminal height should stay stable")
  M.assert_eq(actual.tab_row, expected.tab_row, msg_prefix .. ": tabbar row should stay stable")
  M.assert_eq(actual.tab_col, expected.tab_col, msg_prefix .. ": tabbar col should stay stable")
  M.assert_eq(actual.tab_width, expected.tab_width, msg_prefix .. ": tabbar width should stay stable")
  M.assert_eq(actual.tab_height, expected.tab_height, msg_prefix .. ": tabbar height should stay stable")
end

function M.force_full_footprint_terminal(term_win)
  local term_cfg = vim.api.nvim_win_get_config(term_win)
  local border_footprint = 2
  local full_width = math.max(1, vim.o.columns - border_footprint)
  local full_height = math.max(1, vim.o.lines - border_footprint)

  term_cfg.relative = "editor"
  term_cfg.col = 0
  term_cfg.row = 0
  term_cfg.width = full_width
  term_cfg.height = full_height

  vim.api.nvim_win_set_config(term_win, term_cfg)
end

function M.set_editor_size(columns, lines)
  vim.o.columns = columns
  vim.o.lines = lines
  vim.api.nvim_exec_autocmds("VimResized", {})
  vim.wait(20, function() return false end)
end

function M.cleanup_terminals(ui, ui_state, tabbar)
  local tab_ids = ui_state.traversal_ids()
  for i = #tab_ids, 1, -1 do
    ui.delete_tab(tab_ids[i])
  end
  tabbar.hide()
end

function M.set_form_fields(buf, name_line, cmd_line)
  vim.api.nvim_buf_set_lines(buf, 2, 4, false, {
    name_line,
    cmd_line,
  })
end

function M.assert_form_scaffold(buf, expected_description)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  M.assert_eq(#lines, 6, "task form should render six scaffold lines")
  M.assert_eq(lines[1], expected_description or "Please provide the name and command of the new task", "task form should render description")
  M.assert_truthy(vim.startswith(lines[3], "Name    | "), "task form should render name field prefix")
  M.assert_truthy(vim.startswith(lines[4], "Command | "), "task form should render command field prefix")
  M.assert_eq(lines[6], "<Tab>/<S-Tab> switch  <CR> save  <Esc> close", "task form should render help line")
end

return M
