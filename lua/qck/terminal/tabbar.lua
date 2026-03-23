-- Temporary compatibility shim.
--
-- Tabbar presentation now lives in `qck.ui.tabbar`, but terminal runtime still
-- imports this legacy path during the incremental UI handoff migration.
return require("qck.ui.tabbar")
