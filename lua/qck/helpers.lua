local M = {}

---@class qck.Opts
---@field title? string

function M.notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

function M.is_valid_id(id)
  return type(id) == "number" and id > 0 and id % 1 == 0
end

---@param rec? qck.TerminalRecord
function M.is_valid_record(rec)
  return rec and rec.win and rec.win.buf_valid and rec.win:buf_valid()
end

---@param rec? qck.TerminalRecord
function M.is_window_open(rec)
  return rec and rec.win and rec.win.valid and rec.win:valid()
end

---@param opts? qck.Opts
---@return qck.Opts?
function M.validate_opts(opts)
  if opts == nil then return {} end

  if type(opts) ~= "table" then
    M.notify(
      "new(opts): opts must be a table. falling back to default options.",
      vim.log.levels.ERROR
    )
    return {}
  end

  ---@param title string|nil
  ---@return string|nil
  local function validate_title(title)
    if title == nil then return nil end

    if type(title) ~= "string" then
      M.notify("new(opts): opts.title must be a string", vim.log.levels.ERROR)
      return nil
    end

    if vim.fn.strchars(title) > 1 then
      M.notify(
        "new(opts): title must be a single character",
        vim.log.levels.ERROR
      )
      return nil
    end

    return title
  end

  return { title = validate_title(opts.title) }
end

---@param id number
---@param rec qck.TerminalRecord
function M.title_for(id, rec)
  local title = rec.meta and rec.meta.title
  if title and title ~= "" then
    return ("qck [%d] %s"):format(id, title)
  end
  return ("qck [%d]"):format(id)
end

return M
