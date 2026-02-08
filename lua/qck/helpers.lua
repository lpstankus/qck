local M = {}


function M.notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

function M.is_valid_id(id)
  return type(id) == "number" and id > 0 and id % 1 == 0
end

function M.is_valid_record(rec)
  return rec and rec.win and rec.win.buf_valid and rec.win:buf_valid()
end

function M.is_window_open(rec)
  return rec and rec.win and rec.win.valid and rec.win:valid()
end

function M.validate_opts(opts)
  if opts == nil then return {} end

  if type(opts) ~= "table" then
    M.notify(
      "new(opts): opts must be a table. falling back to default options.",
      vim.log.levels.ERROR
    )
    return {}
  end

  return {}
end

return M
