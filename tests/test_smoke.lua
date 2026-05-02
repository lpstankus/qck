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

T["task runner"] = new_set()
T["task runner"]["selects workspace task"] = scenarios.task_runner_selects_workspace_task
T["task runner"]["handles empty workspace"] = scenarios.task_runner_empty_workspace

T["storage"] = new_set()
T["storage"]["persists workspace task commands across load/save"] = scenarios.storage_roundtrip
T["storage"]["persists across module reload"] = scenarios.storage_persists_across_module_reload
T["storage"]["creates missing data dir on save"] = scenarios.storage_save_creates_missing_data_dir
T["storage"]["writes empty object maps"] = scenarios.storage_empty_state_writes_object_maps
T["storage"]["clears workspace data for current workspace"] = scenarios.clear_storage
T["storage"]["fails invalid load and repairs storage through clear_storage"] = scenarios.invalid_storage_repair

T["ui state"] = new_set()
T["ui state"]["registers categories and traverses tabs"] = scenarios.ui_state_registration_and_traversal

T["ui runtime"] = new_set()
T["ui runtime"]["tracks windows, handles, and layout scaffolding"] = scenarios.ui_runtime_and_layout_scaffolding

T["ui tabbar"] = new_set()
T["ui tabbar"]["renders from ui-owned traversal and active state"] = scenarios.ui_tabbar_renders_from_ui_state

T["ui init"] = new_set()
T["ui init"]["manages internal ui orchestration and rollback"] = scenarios.ui_init_orchestration_contract
T["ui init"]["handles mouse tabbar selection without insert-mode regressions"] = scenarios.ui_mouse_tabbar_selection_contract

T["terminals"] = new_set()
T["terminals"]["manages generic terminals with shared layout"] = scenarios.terminals_and_layout
T["terminals"]["preserves lifecycle watcher behavior and focus routing"] = scenarios.terminal_lifecycle_watchers_and_focus
T["terminals"]["keeps finished task terminal open"] = scenarios.task_terminal_finish_keeps_task_tab_open
T["terminals"]["preserves mixed terminal tabbar after task finish"] = scenarios.task_terminal_finish_preserves_mixed_tabbar
T["terminals"]["pins task terminals before regular terminals"] = scenarios.task_terminals_are_pinned_before_regular_terminals
T["terminals"]["reuses existing task terminal"] = scenarios.task_runner_reuses_existing_task_terminal
T["terminals"]["reopens hidden matching task terminal"] = scenarios.task_runner_reopens_hidden_matching_task_terminal
T["terminals"]["creates task terminals for distinct commands"] = scenarios.task_runner_spawns_distinct_task_terminals_for_distinct_commands
T["terminals"]["prunes invalid terminals and adopts live fallbacks"] = scenarios.terminal_invalidation_and_active_fallbacks

return T
