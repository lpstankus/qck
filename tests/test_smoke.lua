local helpers = require("helpers")
local scenarios = require("scenarios")

local new_set = MiniTest.new_set
local T = new_set({
  hooks = {
    pre_case = helpers.reset_environment,
    post_case = helpers.reset_environment,
  },
})

T["task form"] = new_set()
T["task form"]["creates and overwrites workspace task"] = scenarios.task_form_create_and_overwrite

T["storage"] = new_set()
T["storage"]["persists workspace task commands across load/save"] = scenarios.storage_roundtrip
T["storage"]["clears workspace data for current workspace"] = scenarios.clear_storage
T["storage"]["fails invalid load and repairs storage through clear_storage"] = scenarios.invalid_storage_repair

T["ui state"] = new_set()
T["ui state"]["registers categories and traverses tabs"] = scenarios.ui_state_registration_and_traversal

T["ui runtime"] = new_set()
T["ui runtime"]["tracks windows, handles, and layout scaffolding"] = scenarios.ui_runtime_and_layout_scaffolding

T["terminals"] = new_set()
T["terminals"]["manages generic terminals with shared layout"] = scenarios.terminals_and_layout
T["terminals"]["preserves lifecycle watcher behavior and focus routing"] = scenarios.terminal_lifecycle_watchers_and_focus
T["terminals"]["prunes invalid terminals and adopts live fallbacks"] = scenarios.terminal_invalidation_and_active_fallbacks

return T
