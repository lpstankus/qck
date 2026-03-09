local notify = {}

---@param msg string
---@param level integer|nil
---@return nil
function notify.notify(msg, level)
  vim.notify("QCK: " .. msg, level or vim.log.levels.INFO)
end

return notify
