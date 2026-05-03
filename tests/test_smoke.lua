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
T["task form"]["edits existing workspace task"] = scenarios.task_form_edit_existing_task

T["task runner"] = new_set()
T["task runner"]["selects workspace task"] = scenarios.task_runner_selects_workspace_task
T["task runner"]["runs numbered task directly"] = scenarios.task_runner_runs_numbered_task
T["task runner"]["rejects invalid task numbers"] = scenarios.task_runner_rejects_invalid_task_numbers
T["task runner"]["reuses numbered task terminal"] = scenarios.task_runner_reuses_numbered_task_terminal
T["task runner"]["reorders workspace tasks"] = scenarios.task_runner_reorders_workspace_tasks
T["task runner"]["edits selected task"] = scenarios.task_runner_edits_selected_task
T["task runner"]["edit is no-op for empty workspace"] = scenarios.task_runner_edit_empty_workspace_noops
T["task runner"]["handles empty workspace"] = scenarios.task_runner_empty_workspace

T["storage"] = new_set()
T["storage"]["persists workspace task commands across load/save"] = scenarios.storage_roundtrip
T["storage"]["stores task creation order numbers"] = scenarios.storage_task_ordering
T["storage"]["moves task order numbers"] = scenarios.storage_task_order_moves
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
T["ui tabbar"]["keeps manually reordered T labels"] = scenarios.ui_tabbar_keeps_manually_reordered_t_labels

T["ui init"] = new_set()
T["ui init"]["manages internal ui orchestration and rollback"] = scenarios.ui_init_orchestration_contract
T["ui init"]["handles mouse tabbar selection without insert-mode regressions"] = scenarios.ui_mouse_tabbar_selection_contract

T["terminals"] = new_set()
T["terminals"]["manages generic terminals with shared layout"] = scenarios.terminals_and_layout
T["terminals"]["preserves lifecycle watcher behavior and focus routing"] = scenarios.terminal_lifecycle_watchers_and_focus
T["terminals"]["keeps finished task terminal open"] = scenarios.task_terminal_finish_keeps_task_tab_open
T["terminals"]["preserves mixed terminal tabbar after task finish"] = scenarios.task_terminal_finish_preserves_mixed_tabbar
T["terminals"]["pins task terminals before regular terminals"] = scenarios.task_terminals_are_pinned_before_regular_terminals
T["terminals"]["skips tabbar kind divider"] = scenarios.tabbar_skips_kind_divider
T["terminals"]["reuses existing task terminal"] = scenarios.task_runner_reuses_existing_task_terminal
T["terminals"]["reopens hidden matching task terminal"] = scenarios.task_runner_reopens_hidden_matching_task_terminal
T["terminals"]["creates task terminals for distinct commands"] = scenarios.task_runner_spawns_distinct_task_terminals_for_distinct_commands
T["terminals"]["uses task order for K labels"] = scenarios.task_runner_uses_task_order_for_k_labels
T["terminals"]["updates K labels after task reorder"] = scenarios.task_runner_updates_k_labels_after_reorder
T["terminals"]["prevents manual K label reordering"] = scenarios.task_runner_prevents_manual_k_label_reordering
T["terminals"]["prunes invalid terminals and adopts live fallbacks"] = scenarios.terminal_invalidation_and_active_fallbacks

return T
