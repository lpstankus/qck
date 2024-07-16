---@class qck
local qck = {}

local qck_group = vim.api.nvim_create_augroup("QCK", {})

local cur_buf = nil
local cur_win = nil

function qck.new()
  if cur_buf then qck.kill() end
  SpawnTerm()
  ToggleWindow()
end

function qck.toggle()
  if not cur_buf then
    qck.new()
    return
  end
  ToggleWindow()
end

function qck.kill()
  if cur_win then
    vim.api.nvim_win_close(cur_win, false)
    cur_win = nil
  end
  if cur_buf then
    vim.cmd("bdelete! " .. cur_buf)
    cur_buf = nil
  end
end

function SpawnTerm()
  cur_buf = vim.api.nvim_create_buf(true, true)
  if cur_buf == 0 then
    cur_buf = nil
    vim.notify("QCK: failed to spawn new buffer", vim.log.levels.ERROR)
    return
  end

  vim.cmd("split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, cur_buf)
  vim.cmd("terminal")
  vim.cmd("q")

  vim.api.nvim_create_autocmd(
    { "BufDelete" },
    {
      group = qck_group,
      buffer = cur_buf,
      callback = function(_)
        cur_buf = nil
        cur_win = nil
      end
    }
  )
end

function ToggleWindow()
  if not cur_buf then return end

  if cur_win then
    vim.api.nvim_win_close(cur_win, false)
    cur_win = nil
    return
  end

  local tot_width  = vim.o.columns - 2
  local tot_height = vim.o.lines - 4

  local fraction = 0.8
  local win_width  = math.floor(tot_width * fraction)
  local win_height = math.floor(tot_height * fraction)

  local off_width = math.floor((tot_width - win_width) / 2)
  local off_height = math.floor((tot_height - win_height) / 2) + 1

  cur_win = vim.api.nvim_open_win(
    cur_buf,
    true,
    {
      title = { { "┤ qck terminal ├", "Normal" } },
      relative = 'win', border = "single", style = "minimal",
      width = win_width, height = win_height, col = off_width, row = off_height,
    }
  )

  vim.cmd("startinsert")
end

return qck
