-- Pre-migration compatibility shim.
--
-- Shared float geometry is moving into `lua/qck/ui/layout.lua`, but the active
-- terminal runtime still calls this module until later chunks switch callers.
return require("qck.ui.layout")
