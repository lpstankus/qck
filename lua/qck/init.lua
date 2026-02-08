---@class qck
local qck = {}

local ok, Snacks = pcall(require, "snacks")
if not ok then
  error("QCK: snacks.nvim is required")
end

local cur_term = nil

local function has_term()
  return cur_term and cur_term.buf_valid and cur_term:buf_valid()
end

local function open_term()
  local term_opts = {
    interactive = true,
    auto_close = true,
    win = {
      position = "float",
      relative = "editor",
      border = "single",
      width = 0.8,
      height = 0.8,
      title = "qck terminal",
      title_pos = "center",
    },
  }

  local ok_open, term_or_err = pcall(Snacks.terminal.open, nil, term_opts)
  local term = term_or_err
  if not ok_open or not term then
    local msg = ok_open and "QCK: failed to open terminal"
      or ("QCK: failed to open terminal: " .. tostring(term_or_err))
    vim.notify(msg, vim.log.levels.ERROR)
    return nil
  end

  cur_term = term
  cur_term:on("BufWipeout", function()
    if cur_term == term then
      cur_term = nil
    end
  end, { buf = true })

  return cur_term
end

function qck.toggle()
  if not has_term() then
    open_term()
  else
    cur_term:toggle()
  end
end

function qck.new()
  if has_term() then
    qck.kill()
  end
  open_term()
end

function qck.kill()
  if has_term() then
    cur_term:close()
  end
  cur_term = nil
end

return qck
