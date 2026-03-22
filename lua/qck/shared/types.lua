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

---@class qck.TerminalMeta
---@field auto_scroll boolean
---@field label_id? integer

---@class qck.TerminalRecord
---@field win qck.TerminalHandle
---@field meta qck.TerminalMeta

---@class qck.TerminalCreateOpts
---@field cmd? qck.Command
---@field preserve_mode? boolean
---@field auto_scroll? boolean

---@class qck.StorageTaskState
---@field cmd qck.Command

---@class qck.StorageWorkspaceState
---@field tasks table<string, qck.StorageTaskState>

---@class qck.StorageState
---@field version string
---@field workspaces table<string, qck.StorageWorkspaceState>

return {}
