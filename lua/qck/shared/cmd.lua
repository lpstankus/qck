local cmd = {}

---@param value qck.Command
---@return qck.Command
function cmd.clone(value)
  if type(value) == "string" then
    return value
  end

  local copy = {}
  for i, part in ipairs(value) do
    copy[i] = part
  end
  return copy
end

---@param value any
---@return qck.Command|nil
function cmd.normalize(value)
  if type(value) == "string" then
    if vim.trim(value) == "" then
      return nil
    end
    return value
  end

  if type(value) ~= "table" or #value == 0 then
    return nil
  end

  local parsed = {}
  for i, part in ipairs(value) do
    if type(part) ~= "string" or vim.trim(part) == "" then
      return nil
    end
    parsed[i] = part
  end

  return parsed
end

---@param value any
---@param context string
---@param notify fun(msg: string, level?: integer)
---@return qck.Command|nil
function cmd.validate(value, context, notify)
  if type(value) == "string" then
    if vim.trim(value) == "" then
      notify(context .. ": cmd must not be empty", vim.log.levels.ERROR)
      return nil
    end
    return value
  end

  if type(value) ~= "table" then
    notify(context .. ": cmd must be a string or a list of strings", vim.log.levels.ERROR)
    return nil
  end

  if #value == 0 then
    notify(context .. ": cmd list must not be empty", vim.log.levels.ERROR)
    return nil
  end

  local parsed = {}
  for i, part in ipairs(value) do
    if type(part) ~= "string" or vim.trim(part) == "" then
      notify(("%s: cmd[%d] must be a non-empty string"):format(context, i), vim.log.levels.ERROR)
      return nil
    end
    parsed[i] = part
  end

  return parsed
end

return cmd
