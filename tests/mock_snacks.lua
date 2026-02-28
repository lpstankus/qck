local M = {}

local handles = {}

local function create_handle(id, cmd)
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

  local function open_win()
    return vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 1,
      col = math.max(1, id * 2),
      width = 40,
      height = 10,
      style = "minimal",
      border = "single",
      focusable = true,
      noautocmd = true,
    })
  end

  local handle = {
    buf = buf,
    win = open_win(),
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
        local handle = create_handle(id, cmd)
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

return M
