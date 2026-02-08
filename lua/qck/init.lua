---@class qck
local qck = {}

local ok, Snacks = pcall(require, "snacks")
if not ok then
  error("QCK: snacks.nvim is required")
end

local qck_group = vim.api.nvim_create_augroup("QCK", {})

local cur_buf = nil
local cur_win = nil

local function has_buf()
  return cur_buf and vim.api.nvim_buf_is_valid(cur_buf)
end

local function has_window()
  return cur_win and cur_win.valid and cur_win:valid()
end

local function spawn_term()
  cur_buf = vim.api.nvim_create_buf(true, false)
  if cur_buf == 0 then
    cur_buf = nil
    vim.notify("QCK: failed to spawn new buffer", vim.log.levels.ERROR)
    return
  end

  vim.bo[cur_buf].bufhidden = "hide"

  local job_started = false
  local shells = {
    vim.o.shell,
    vim.env.SHELL,
    "bash",
    "sh",
  }

  for _, shell_cmd in ipairs(shells) do
    if shell_cmd and shell_cmd ~= "" then
      local ok_jobstart, job_id = pcall(vim.api.nvim_buf_call, cur_buf, function()
        return vim.fn.jobstart(shell_cmd, { term = true })
      end)
      if ok_jobstart and type(job_id) == "number" and job_id > 0 then
        job_started = true
        break
      end
    end
  end

  if not job_started then
    vim.notify("QCK: failed to start terminal shell", vim.log.levels.ERROR)
    vim.api.nvim_buf_delete(cur_buf, { force = true })
    cur_buf = nil
    return
  end

  vim.api.nvim_create_autocmd(
    { "BufDelete", "BufWipeout" },
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

local function toggle_window()
  if not has_buf() then return end

  if has_window() then
    cur_win:hide()
    cur_win = nil
    return
  end

  cur_win = Snacks.win({
    buf = cur_buf,
    enter = true,
    show = false,
    relative = "editor",
    position = "float",
    border = "single",
    width = 0.8,
    height = 0.8,
    title = "qck terminal",
    title_pos = "center",
    on_close = function()
      cur_win = nil
    end,
  })
  cur_win:show()

  vim.cmd("startinsert")
end

function qck.new()
  if has_buf() then qck.kill() end
  spawn_term()
  toggle_window()
end

function qck.toggle()
  if not has_buf() then
    qck.new()
    return
  end
  toggle_window()
end

function qck.kill()
  if has_window() then
    cur_win:close({ buf = false })
    cur_win = nil
  end
  if has_buf() then
    vim.api.nvim_buf_delete(cur_buf, { force = true })
    cur_buf = nil
  end
end

return qck
