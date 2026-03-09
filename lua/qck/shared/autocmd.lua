local autocmd = {}

local group = vim.api.nvim_create_augroup("qck", { clear = true })

---@param events string|string[]
---@param opts table
---@return integer
function autocmd.create(events, opts)
  opts = opts or {}
  opts.group = group
  return vim.api.nvim_create_autocmd(events, opts)
end

---@param id integer|nil
---@return nil
function autocmd.delete(id)
  if type(id) ~= "number" then
    return
  end
  pcall(vim.api.nvim_del_autocmd, id)
end

return autocmd
