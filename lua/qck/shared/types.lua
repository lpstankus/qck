---@meta

---@alias qck.Command string|string[]

---@class qck.TerminalHandle
---@field buf integer|fun(self: qck.TerminalHandle): integer
---@field win integer|fun(self: qck.TerminalHandle): integer
---@field buf_valid fun(self: qck.TerminalHandle): boolean
---@field valid fun(self: qck.TerminalHandle): boolean
---@field show fun(self: qck.TerminalHandle)
---@field toggle fun(self: qck.TerminalHandle)
---@field close fun(self: qck.TerminalHandle)
---@field on? fun(self: qck.TerminalHandle, event: string, cb: fun(...), opts?: table)

---@class qck.StorageTaskState
---@field cmd qck.Command
---@field order integer

---@class qck.StorageTaskEntry
---@field name string
---@field cmd qck.Command
---@field order integer

---@class qck.StorageWorkspaceState
---@field tasks table<string, qck.StorageTaskState>

---@class qck.StorageState
---@field version string
---@field workspaces table<string, qck.StorageWorkspaceState>

return {}
