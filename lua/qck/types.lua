---@meta

---@alias qck.Command string|string[]
---@alias qck.TerminalKind "default"|"long_running"

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
---@field kind qck.TerminalKind
---@field builder_type? string
---@field auto_scroll boolean
---@field group_label_id? integer

---@class qck.TerminalRecord
---@field win qck.TerminalHandle
---@field meta qck.TerminalMeta

---@class qck.BuilderDefinition
---@field cmd qck.Command
---@field auto_scroll? boolean

---@class qck.BuilderBuildOpts
---@field force_new? boolean
---@field auto_scroll? boolean

---@class qck.TerminalCreateOpts
---@field kind? qck.TerminalKind
---@field builder_type? string
---@field cmd? qck.Command
---@field preserve_mode? boolean
---@field auto_scroll? boolean

---@class qck.StorageBuilderState
---@field cmd qck.Command

---@class qck.StorageWorkspaceState
---@field builders table<string, qck.StorageBuilderState>

---@class qck.StorageState
---@field version string
---@field workspaces table<string, qck.StorageWorkspaceState>

return {}
