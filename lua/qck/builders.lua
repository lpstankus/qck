local builders = {}

local configured_builders = {}

---@param cmd string|string[]
---@return string|string[]
local function clone_cmd(cmd)
  if type(cmd) == "string" then
    return cmd
  end

  local copy = {}
  for i, part in ipairs(cmd) do
    copy[i] = part
  end
  return copy
end

---@param definitions table<string, table>
---@return nil
function builders.set_definitions(definitions)
  configured_builders = {}

  for builder_type, builder in pairs(definitions or {}) do
    configured_builders[builder_type] = {
      cmd = clone_cmd(builder.cmd),
      auto_scroll = builder.auto_scroll,
      title = builder.title,
    }
  end
end

---@param builder_type string
---@return table|nil
function builders.get_definition(builder_type)
  local builder = configured_builders[builder_type]
  if not builder then
    return nil
  end

  return {
    cmd = clone_cmd(builder.cmd),
    auto_scroll = builder.auto_scroll,
    title = builder.title,
  }
end

---@return table<string, table>
function builders.get_definitions()
  local out = {}
  for builder_type, _ in pairs(configured_builders) do
    out[builder_type] = builders.get_definition(builder_type)
  end
  return out
end

return builders
