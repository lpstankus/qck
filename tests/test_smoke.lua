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

T["tasks"] = new_set()
T["tasks"]["hydrates persisted workspace task definitions"] = scenarios.hydrate_workspace_tasks

T["terminals"] = new_set()
T["terminals"]["manages default and task terminals with shared layout"] = scenarios.terminals_and_layout

T["storage"] = new_set()
T["storage"]["clears workspace data for current workspace"] = scenarios.clear_storage
T["storage"]["fails invalid load and repairs storage through clear_storage"] = scenarios.invalid_storage_repair

return T
