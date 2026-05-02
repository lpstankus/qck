local M = {}

local handles = {}

---@param win_opts table|nil
---@return vim.api.keyset.win_config
local function normalize_win_config(id, win_opts)
  local conf = vim.tbl_extend("force", {
    relative = "editor",
    row = 1,
    col = math.max(1, id * 2),
    width = 40,
    height = 10,
    style = "minimal",
    border = "single",
    focusable = true,
  }, win_opts or {})

  conf.row = math.floor(tonumber(conf.row) or 1)
  conf.col = math.floor(tonumber(conf.col) or math.max(1, id * 2))
  conf.width = math.max(1, math.floor(tonumber(conf.width) or 40))
  conf.height = math.max(1, math.floor(tonumber(conf.height) or 10))
  conf.position = nil
  conf.noautocmd = true
  return conf
end

local function create_handle(id, cmd, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  if type(cmd) == "string" then
    lines[1] = "cmd: " .. cmd
  elseif type(cmd) == "table" then
    lines[1] = "cmd: " .. table.concat(cmd, " ")
  else
    lines[1] = "cmd:"
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local win_opts = type(opts) == "table" and opts.win or nil
  local win_config = normalize_win_config(id, win_opts)

  local function open_win()
    return vim.api.nvim_open_win(buf, false, vim.deepcopy(win_config))
  end

  local handle = {
    buf = buf,
    win = open_win(),
    auto_close = not (type(opts) == "table" and opts.auto_close == false),
    _autocmd_ids = {},
  }

  function handle:buf_valid()
    return type(self.buf) == "number" and vim.api.nvim_buf_is_valid(self.buf)
  end

  function handle:valid()
    return type(self.win) == "number" and vim.api.nvim_win_is_valid(self.win)
  end

  function handle:show()
    if not self:buf_valid() then
      return
    end
    if self:valid() then
      return
    end
    self.win = open_win()
  end

  function handle:toggle()
    if self:valid() then
      local win = self.win
      self.win = nil
      vim.api.nvim_win_close(win, true)
      return
    end
    self:show()
  end

  function handle:close()
    if self:valid() then
      local win = self.win
      self.win = nil
      vim.api.nvim_win_close(win, true)
    end
    if self:buf_valid() then
      local target_buf = self.buf
      self.buf = nil
      vim.api.nvim_buf_delete(target_buf, { force = true })
    end
  end

  function handle:on(event, cb, opts)
    local autocmd_id = vim.api.nvim_create_autocmd(event, {
      buffer = opts and opts.buf and self.buf or nil,
      callback = cb,
      once = false,
    })
    self._autocmd_ids[#self._autocmd_ids + 1] = autocmd_id
  end

  return handle
end

function M.install()
  package.loaded.snacks = {
    terminal = {
      open = function(cmd, opts)
        local id = type(opts) == "table" and opts.count or 1
        local handle = create_handle(id, cmd, opts)
        handles[id] = handle
        return handle
      end,
    },
  }
end

function M.reset()
  for id, handle in pairs(handles) do
    pcall(function() handle:close() end)
    handles[id] = nil
  end
end

function M.get_handles()
  return handles
end

function M.finish_handle(handle)
  if type(handle) ~= "table" then
    return
  end

  if handle.auto_close == false then
    return
  end

  if type(handle.win) ~= "number" then
    return
  end

  local win = handle.win
  handle.win = nil
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

return M
