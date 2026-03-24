-- Thin compatibility wrapper during the UI handoff migration.
--
-- Focus, resize, and tabbar interaction wiring now live in `qck.ui`. This
-- module remains only as a stable import path for callers that still require
-- `qck.app.focus`.
local ui = require("qck.ui")

local focus = {}

---@return nil
function focus.setup()
  ui.setup()
end

return focus
