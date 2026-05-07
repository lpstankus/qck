local rerender = {}

---@param handle any
---@return integer|nil
local function get_buffer_id(handle)
  if type(handle) ~= "table" then
    return nil
  end

  if type(handle.buf) == "number" and vim.api.nvim_buf_is_valid(handle.buf) then
    return handle.buf
  end

  if type(handle.buf) == "function" then
    local ok, bufnr = pcall(function() return handle:buf() end)
    if ok and type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) then
      return bufnr
    end
  end

  return nil
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

---@param bufnr integer|nil
---@return integer|nil
local function get_terminal_channel(bufnr)
  if not bufnr then
    return nil
  end

  local chan = vim.b[bufnr].terminal_job_id
  if type(chan) ~= "number" or chan <= 0 then
    chan = tonumber(vim.bo[bufnr].channel)
  end
  if type(chan) ~= "number" or chan <= 0 then
    return nil
  end

  return chan
end

---@param handle any
---@return nil
function rerender.request_agent(handle)
  vim.schedule(function()
    local winid = get_window_id(handle)
    local bufnr = get_buffer_id(handle)
    if not winid and not bufnr then
      return
    end

    if winid then
      local chan = get_terminal_channel(bufnr)
      if chan then
        pcall(vim.fn.jobresize, chan, vim.api.nvim_win_get_width(winid), vim.api.nvim_win_get_height(winid))
      end

      pcall(vim.api.nvim_win_call, winid, function()
        vim.cmd("redraw!")
      end)
    end
    pcall(vim.api.nvim__redraw, {
      win = winid,
      buf = bufnr,
      valid = false,
      flush = true,
      cursor = true,
    })
  end)
end

return rerender
