# Repository Guidelines

## Project Structure & Module Organization
This repository is a Neovim plugin written in Lua.

- `lua/qck/init.lua`: public plugin API (`setup`, `clear_storage`, `new`, `new_task`, `run_task`, `open`, `close`, `toggle`, `cycle_next`, `cycle_prev`, `switch_focus`).
- `lua/qck/shared/autocmd.lua`: shared plugin autocmd wrapper exposing a single `qck` augroup.
- `lua/qck/shared/cmd.lua`: shared command normalization/cloning/validation helpers (`string` or string-list commands).
- `lua/qck/shared/keymaps.lua`: shared mapping parsing/state/application helpers for user-configured buffer mappings.
- `lua/qck/shared/notify.lua`: shared `QCK:` notification helper.
- `lua/qck/shared/types.lua`: shared EmmyLua type aliases/classes.
- `lua/qck/app/terminal/init.lua`: caller-side ad hoc terminal creation flow that builds initial Snacks opts, creates raw handles, and hands them off to the UI for ownership.
- `lua/qck/app/terminal/service.lua`: raw `snacks.terminal` handle creation/cleanup adapter used by `app/terminal/init.lua`.
- `lua/qck/ui/runtime.lua`: UI runtime state for visible content/tabbar winids, owned-handle registration, and watcher bookkeeping.
- `lua/qck/ui/layout.lua`: UI-owned shared float geometry for content/tabbar layout math.
- `lua/qck/ui/state.lua`: pure internal UI state for category registration, tab metadata, active-tab fallback, display-id reuse, and traversal ordering.
- `lua/qck/ui/init.lua`: internal UI orchestration entrypoints for category registration, attach/show/hide/toggle flows, active-tab selection, deletion, motion, winid-based tabbar focus routing, UI-owned global/per-tab watcher lifecycle, terminal-buffer mapping ownership, and terminal-backed visibility/layout orchestration after handoff.
- `lua/qck/ui/tabbar.lua`: UI-owned tabbar presentation that builds/render rows from `ui/state.lua` and routes built-in row actions back through `ui/init.lua`.
- `lua/qck/ui/types.lua`: UI-local EmmyLua aliases/classes for categories, tab ids, and tab metadata.
- `lua/qck/tasks/storage.lua`: workspace-persistent storage for workspace-created task definitions.
- `lua/qck/tasks/form.lua`: floating task-creation form UI (name/cmd fields, Tab cycling, overwrite confirmation, workspace save).
- `lua/qck/tasks/runner.lua`: floating task-runner selector UI for current-workspace saved tasks; normal-mode-only navigation, `<CR>` task-terminal spawn, and `<Esc>` close.
- `lua/qck/app/setup.lua`: setup-time wiring for Snacks bootstrapping, UI setup, mapping parsing, UI/tabbar mapping configuration, and storage load.
- `tests/mock_snacks.lua`: deterministic Snacks terminal mock for headless `mini.test` coverage/integration runs.
- `tests/helpers.lua`: shared `mini.test` helper utilities for storage seeding, environment reset, and repeated UI/layout assertions.
- `tests/test_smoke.lua`: `mini.test` suite covering the current smoke-test behavior in isolated cases.
- `tests/scenarios.lua`: shared smoke-behavior scenario functions reused by both the `mini.test` suite and the coverage runner.
- `tests/minitest.lua`: headless `mini.test` bootstrap/runner with vendored dependency path setup.
- `tests/coverage.lua`: headless scenario runner that executes the same smoke assertions under vendored `luacov`.
- `tests/luacov_report.lua`: headless coverage-report generator using vendored `luacov`.
- `tests/smoke.lua`: deprecated compatibility shim that warns and forwards to the `mini.test` runner.
- `tests/vendor/`: vendored test-only dependencies (`mini.test` and `luacov`).
- `tests/.tmp/`: ignored test-only data root used to keep headless storage tests away from the real Neovim data directory.
- `LICENSE`: project license.

Keep new runtime code under `lua/qck/`. `init.lua` should remain the public entrypoint; internal behavior should be split by package responsibility across `shared/`, `tasks/`, `ui/`, and `app/`.

## Build, Test, and Development Commands
There is no build system or package manifest. Use Neovim headless/manual checks:

- `nvim --headless --clean +"set rtp+=." +"lua require('qck')" +qa`
  Verifies plugin load and runtime syntax (requires `snacks.nvim` on `runtimepath`).
- `nvim --headless --clean +"set rtp+=/path/to/snacks.nvim" +"set rtp+=." +"lua require('qck')"`
  Verifies behavior with Snacks dependency on `runtimepath`.
- `luac -p $(rg --files lua/qck -g '*.lua')`
  Fast syntax check for all Lua modules, including packaged subdirectories.
- `nvim --headless --clean -u NONE +"lua dofile('tests/minitest.lua')"`
  Runs the mocked `mini.test` suite headlessly with vendored `mini.test` and isolated `XDG_DATA_HOME`.
- `nvim --headless --clean -u NONE +"lua dofile('tests/coverage.lua')"`
  Runs the same smoke-behavior scenarios under vendored `luacov` with isolated `XDG_DATA_HOME` to collect line coverage stats.
- `nvim --headless --clean -u NONE +"lua dofile('tests/luacov_report.lua')" +qa`
  Generates the `luacov` line-coverage report after `tests/coverage.lua` has written coverage stats.
- `nvim --headless --clean -u NONE +"set rtp+=." +"luafile tests/smoke.lua"`
  Deprecated compatibility entrypoint that warns and forwards to `tests/minitest.lua`.
- `nvim --clean +"set rtp+=."`
  Opens an interactive clean session for manual testing.

## Coding Style & Naming Conventions
- Language: Lua (Neovim API via `vim.*`).
- Indentation: 2 spaces, no tabs.
- Prefer `local` functions/state; expose only intentional public API on `qck`.
- Use `snake_case` for functions/locals (`cycle_next`, `current_id`).
- Keep window/terminal side effects centralized and explicit.
- Public API comments in `lua/qck/init.lua` should stay user-facing: a one-line summary, brief parameter notes, and a small usage example for each exported function.

## Testing Guidelines
Minimal automated coverage is available under `tests/`. Validate changes with:

1. Mocked headless `mini.test` suite (`tests/minitest.lua`).
2. Coverage collection (`tests/coverage.lua`).
3. Coverage report generation (`tests/luacov_report.lua`).
4. Headless load check.
5. Manual workflow checks: `new`, `open`, `close`, `toggle`, `cycle_next`, `cycle_prev`, `new_task`, `run_task`, `clear_storage`.
6. Multi-terminal visibility checks:
    - creating/opening a different terminal should hide the previously visible terminal window,
    - `toggle` should affect only the current terminal visibility,
    - stale active-id fallback should adopt the first live terminal instead of creating a replacement stale-id terminal,
    - `toggle()` with no live terminals should create and show a new terminal plus tabbar,
    - moving focus to a non-qck window (for example `<C-w>h`) should hide qck terminal and tabbar windows,
    - terminal width should shrink by the tabbar width and shift right so the combined terminal+tabbar footprint fills the bordered editor footprint,
    - resizing from small -> large and from large -> small should preserve qck terminal/tabbar geometry when the resized terminal is hidden and reopened,
    - resize regression coverage should simulate the observed failure mode where the terminal temporarily expands beyond the allowed bordered editor footprint and covers the tabbar area before deferred qck layout repair runs.
7. Tab bar checks:
    - opens/closes with the visible terminal window,
    - closes when the terminal window is closed manually (for example `:q`),
    - closing the tabbar window manually (for example `:q`) should hide the current terminal window,
    - `switch_focus()` should route focus terminal <-> tabbar and fall back to the terminal from a non-qck window,
    - pressing `<Esc>` in the tabbar focuses the current terminal window,
    - left-clicking a tabbar row should select that terminal and place focus in the terminal window in terminal mode,
    - pressing `K`/`J` in the tabbar should move the selected terminal up/down within the single terminal list,
    - `T*` labels should stay with the same terminal when rows are reordered,
    - creating a new terminal should assign the lowest missing `T*` label number for the current session,
    - current terminal line uses full-row reverse highlight.
8. Storage behavior checks:
   - unsupported or invalid schema should fail load and warn users,
   - `clear_storage()` should clear persisted data for current workspace,
   - saves should create the parent data directory when it is missing,
   - empty storage maps should be written as JSON objects, not arrays,
   - no implicit storage reset should happen on failed load.
9. Terminal exit checks (`exit`, `exit 1`) to verify close/error behavior.
10. Task form checks:
    - `new_task()` opens a floating form with task name/command fields,
    - calling `new_task()` while the form is already open should focus/reuse the same window,
    - edit mode opens the same form with an edit title and prefilled task name/command,
    - edit mode saves command changes in place and renames by removing the original task name,
    - edit mode rename collisions require the same two-step overwrite confirmation,
    - form scaffold lines (description/prefix/help) should be rendered and preserved,
    - `Tab`/`Shift-Tab` cycles fields in both normal and insert modes,
    - first save on duplicate name warns and keeps form open,
    - validation errors (for example empty task name) keep the form open and clear pending duplicate overwrite confirmation,
    - after changing form contents following a duplicate warning, overwrite must require confirmation again,
    - second save on the same duplicate name overwrites and closes form,
    - successful save persists task command for the current workspace only.
11. Task runner checks:
    - `run_task()` opens a floating selector with only current-workspace saved tasks,
    - calling `run_task()` while the selector is already open should focus/reuse the same window,
    - task rows are sorted by stored workspace creation order, show compact `1.`, `2.`, ... prefixes, and the selected row uses reverse highlight after the number,
    - `j`/`k` navigate within task rows without wrapping beyond bounds,
    - `J`/`K` swap the selected task down/up, keep the moved task selected, and persist the new workspace order,
    - the selector is normal-mode-only and read-only,
    - `<CR>` on a task row should spawn and focus a `K#` task terminal with the selected command and close the selector,
    - `e` on a task row should close the selector and open the task form in edit mode for that task,
    - selecting a task whose saved task identity already has a live `K#` terminal should focus/reuse that terminal instead of spawning another one,
    - task terminals should use `auto_close = false` so command completion keeps Neovim's default exited-command prompt open for user input,
    - task terminals should be pinned before regular terminals in traversal/tabbar order (`K#` before `T#`),
    - task terminal `K#` labels should match the selected saved task's current workspace order number and update when task order changes,
    - `<CR>` on an empty workspace should be a no-op,
    - `<Esc>` and `q` close the selector.
12. Storage-only task checks:
    - storage load/save round-trips normalized workspace task commands,
    - storage load/save round-trips workspace task creation-order numbers,
    - storage load backfills missing task order numbers deterministically for older task entries,
    - storage survives a fresh module reload in the same data directory,
    - workspace task data remains isolated per working directory.
13. UI state checks:
    - category registration is ordered and idempotent only for matching metadata,
    - category labels stay unique across categories,
    - registered tabs capture category label/display metadata,
    - per-category ordering drives derived global traversal order,
    - category display ids reuse the lowest missing value after deletion,
    - stale-or-nil active tab fallback adopts the first live tab in traversal order.
14. UI runtime/layout checks:
    - runtime tracks visible content/tabbar winids and clears stale winids lazily on read,
    - runtime keeps owned-handle and watcher bookkeeping isolated from caller mutation,
    - UI layout math matches the existing shared terminal/tabbar float footprint.
15. UI tabbar checks:
     - tabbar row order is derived from `ui.state` traversal order,
     - row labels come from category label plus category display id,
     - active-row highlight follows `ui.state` active-tab selection,
     - task and regular terminal groups are separated by a box-drawing divider that keyboard and mouse selection skip.
16. UI init contract checks:
    - `attach_and_show()` registers a new tab, makes it active, shows it immediately, and hides the previously visible tab,
    - `show()`/`hide()`/`toggle()` preserve active-tab selection while updating visibility,
    - `set_active_tab()` swaps visible content without reordering when UI is open,
    - `move_tab()` rerenders tabbar order and rejects invalid directions,
    - `delete_tab()` adopts the next live tab and hides the UI when the last tab is removed,
    - failed `attach_and_show()` rolls back tab registration, active selection, visibility, owned-handle bookkeeping, and watcher state.
17. UI watcher ownership checks:
    - global focus-leave and resize watchers are installed through `ui.init`,
    - per-tab watcher bookkeeping covers buffer invalidation plus visible content/tabbar close behavior,
    - hiding or replacing a visible tab clears only visibility watchers while preserving invalidation cleanup,
    - terminal-backed visibility swaps suppress focus-leave auto-hide while the swap is in progress,
    - deleting a tab clears all watcher bookkeeping for that tab.

Additional tests should be placed under `tests/` and documented in this section.

## Current Architecture Findings
- `snacks.nvim` is required at runtime; plugin load should fail early if unavailable.
- Package boundaries are:
  - `shared/`: leaf utilities only, with no imports from `tasks/`, `ui/`, or `app/`,
  - `ui/`: tab/category state, layout, tabbar rendering, visibility, focus, and watcher orchestration,
  - `tasks/`: workspace-persistent task storage, the floating task creation form, and the current-workspace task runner selector,
  - `app/`: setup-time wiring plus caller-side terminal creation/handoff flow and the raw Snacks adapter used before UI ownership begins.
- State validity checks guard terminal-handle method calls with `pcall`, so stale/invalid handle behavior cannot break prune/cycle paths.
- `app/terminal/service.lua` closes partially opened terminal handles when handle initialization fails, preventing leaked untracked terminal resources.
- Workspace persistence lives in `tasks/storage.lua` (`stdpath("data") .. "/qck.json"`) and stores per-workspace saved task commands plus task creation-order numbers created through `qck.new_task()`.
- `storage.load()` / `storage.save()` return `(ok, err)` and track `storage.last_error`, so callers can report concrete persistence failure details.
- `storage.save()` creates the parent data directory before writing and preserves empty workspace maps as JSON objects (`{}`), avoiding accidental array-shaped storage.
- Storage loading is fail-fast on unsupported/invalid schema and does not mutate files automatically.
- `qck.clear_storage()` is the explicit user-triggered storage reset entrypoint for current workspace state.
- Shared EmmyLua type aliases/classes live in `lua/qck/shared/types.lua`, and module annotations use these types to tighten internal contracts for LuaLS.
- `lua/qck/init.lua` is limited to the public API surface plus imports and delegates internal setup/terminal creation behavior into `app/` modules.
- Command normalization/cloning/validation is centralized in `lua/qck/shared/cmd.lua` and reused by `tasks/form.lua` and `tasks/storage.lua`.
- Shared `QCK:` notifications are centralized in `lua/qck/shared/notify.lua` and reused by `init.lua`, `tasks/form.lua`, and `app/`.
- Mapping-state diff/cleanup helpers are centralized in `lua/qck/shared/keymaps.lua` and reused by both terminal and tabbar mapping application paths.
- Tab bar presentation renders through `ui/tabbar.lua`, and the close/invalidation watcher lifecycle lives in `ui/init.lua`.
- Floating window geometry source-of-truth lives in `lua/qck/ui/layout.lua`.
- Shared terminal/tabbar layout reserves a two-column gap between the tabbar and terminal so both float borders remain visually distinct inside the original terminal footprint.
- Shared terminal/tabbar layout uses `relative = "editor"` and a full-editor bordered footprint while keeping the tabbar inside that total size budget.
- All plugin autocmds share a single `qck` augroup via `shared/autocmd.lua`; modules track and delete autocmd ids for targeted cleanup.
- When switching terminals, hiding the previous window (`toggle`) is safer than closing it (`close`), because closing may wipe the buffer and terminate the terminal job.
- `noautocmd` is valid when creating the tab bar float (`nvim_open_win`), but must not be passed to `nvim_win_set_config` for an existing window.
- `qck.new()` creates a new ad hoc terminal tab and does not accept task or terminal options.
- Terminal runtime manages ad hoc `T#` terminals and task-runner `K#` terminals through the shared UI category model.
- UI setup registers the `K` task category before the `T` terminal category so task terminals stay pinned before regular terminals in traversal and tabbar order.
- Task support is intentionally limited to `qck.new_task()`, `qck.run_task()`, `tasks/storage.lua`, and `qck.clear_storage()`; `run_task()` executes saved commands in `K#` task terminals, with no task hydration or override runtime.
- `qck.new_task()` opens `tasks/form.lua` floating UI for creating workspace-scoped tasks; form saves trimmed task commands into workspace storage.
- The task form has create and edit modes; edit mode is opened from the runner, pre-fills the selected task, and renames by removing the original task key after validation/overwrite confirmation.
- `qck.run_task()` opens `tasks/runner.lua` floating UI for selecting current-workspace saved tasks in stored creation order; the selector is read-only, normal-mode-only, uses `j`/`k` navigation, `J`/`K` persisted task reordering, `<CR>` task-terminal spawn, and `<Esc>`/`q` close.
- Task runner rows display compact workspace order prefixes (`1.`, `2.`, ...), while storage keeps the underlying creation-order metadata with each task entry.
- Task-run terminal reuse is keyed by saved task identity (`workspace` + task name), not command value; two task names with the same command get separate live `K#` terminals.
- Task-run terminal `K#` labels use the saved task's current workspace order number, so live task terminals relabel when `J`/`K` reorders tasks in the runner.
- Task-run terminals use `auto_close = false`, so completed commands keep the terminal window/tabbar visible and wait on Neovim's default command-exited prompt until the user acts.
- Task form duplicate protection is explicit two-step overwrite: first submit on an existing task warns, second submit with the same name confirms overwrite.
- `tasks/form.lua` keeps runtime UI state in a single local state table (`bufnr`/`winid`/selection/pending overwrite/autocmd ids) instead of scattered module globals.
- Task form submit sanitization preserves support for legacy inline labels (`Name: ...` / `Command: ...`) by normalizing to current prefixed scaffold rows before validation/save.
- `tasks/form.lua` writes workspace task commands directly through `tasks/storage.lua` and checks duplicates against persisted workspace data.
- `app/terminal/service.lua` only creates raw Snacks terminal handles (plus adapter-level cleanup), and `app/terminal/init.lua` immediately hands those handles off through `ui/init.lua`.
- Tabbar presentation is UI-owned:
  - `ui/tabbar.lua` builds row order, row labels, and active-row highlighting from `ui.state` traversal/category metadata,
  - built-in row actions call UI-owned selection/deletion/reorder/focus entrypoints directly.
- Tabbar left-click selection routes focus to the clicked terminal window and enters terminal mode so typing can continue immediately.
- Tabbar supports manual reordering in normal mode with `K` (move selected terminal up) and `J` (move selected terminal down) within the single terminal list.
- User mappings configured via `qck.setup({ mappings = ... })` are normalized in `app/setup.lua`, then applied through `ui/init.lua` for terminal buffers and `ui/tabbar.lua` for the tabbar buffer:
  - legacy entries (`lhs = rhs`) default to terminal `n`+`t`,
  - mapping specs (`lhs = { rhs = ..., mode = ... }`) allow terminal-mode scoping (`n`, `t`, or both),
  - tabbar user mappings remain normal-mode-only.
- Tabbar cursor placement lands on the centered row label's numeric part (or first non-space character when no number is present).
- Tabbar includes a built-in normal-mode `<Esc>` mapping that returns focus to the current terminal window.
- `ui/init.lua` now owns both global (`WinEnter`/`BufEnter`/`TabEnter`, `VimResized`) and per-tab (`BufWipeout`, content `WinClosed`, tabbar `WinClosed`) watcher installation/cleanup, including recoverable-hide vs invalidation-delete behavior.
- `plans/2-ui-contract-refactor-plan.md` now includes the explicit pre-migration watcher source/lifetime/cleanup contract for `WinEnter`/`BufEnter`/`TabEnter`, `VimResized`, terminal `WinClosed`, tabbar `WinClosed`, and terminal `BufWipeout`, including which paths may hide UI versus delete terminal state.
- Internal helper functions in `app/setup.lua` stay local to the module unless they are part of the returned module API.
- Visual labels are UI-only; public APIs `open()`, `close()`, and `toggle()` are active-tab-only wrappers over the current UI tab selection.
- `qck.open()`, `qck.close()`, and `qck.toggle()` adopt the first live terminal when the stored active id is stale or `nil`; `open()`/`toggle()` create and show a new terminal only when no live terminals exist at all.
- `qck.close()` accepts no id argument and closes only the active terminal; when no active terminal exists it warns and becomes a no-op.
- `qck.cycle_next()` / `qck.cycle_prev()` request mode preservation; `qck.new()` requests it only when a qck terminal window is currently open.
- `plans/2-ui-handoff-contract.md` is the written source of truth for the upcoming internal UI handoff migration: it locks ownership transfer, rollback guarantees, recoverable-vs-invalid semantics, stale-active fallback, category registration rules, traversal rules, preserved-mode behavior, create-vs-reopen behavior, mapping ownership, and watcher lifetimes before runtime ownership moves.
- Current runtime ownership is UI-led for watcher, focus, tabbar, layout, visibility, terminal traversal, and terminal-buffer mapping behavior; terminal-specific code is limited to raw handle creation/cleanup.
- `lua/qck/ui/state.lua` now provides a dark, pure-state UI registry that tracks registered categories, stable never-reused `tab_id`s, reusable per-category display ids, category-local ordering, derived global traversal, terminal-handle lookup, and active-tab fallback without taking over runtime window orchestration yet.
- `lua/qck/ui/runtime.lua` now provides the UI-owned runtime state container for visible content/tabbar window ids, reusable tabbar surface bookkeeping, generic owned-handle registration, and copied watcher registries.
- `lua/qck/ui/init.lua` now makes the internal handoff contract executable for this chunk: it can register categories, attach caller-created handles, manage active-tab visibility for UI-owned tabs, expose thin public-behavior wrappers (`create/open/toggle/close/cycle`) for `qck.init`, roll back failed `attach_and_show()` attempts, and route focus switching through UI-owned content/tabbar winids.
- `ui/init.lua` now owns watcher installation and cleanup for both global focus/resize behavior and per-tab buffer/window lifecycle tracking; focus/resize behavior no longer depends on app-level bridges.
- UI-owned watcher helpers explicitly separate long-lived global watcher state from per-tab watcher state, and terminal-backed window swaps temporarily suppress focus-leave auto-hide so internal hide/show churn does not collapse the UI.
- `ui/state.lua` is now the sole owner of terminal-tab identity, ordering, cycling, active-tab fallback, and `K#`/`T#` display ids.
- `ui/init.lua` resolves active-tab-only behavior strictly through `ui/state.lua`; no terminal-id compatibility layer remains in runtime flows.
- deleting the active tab now always follows `ui.state` traversal fallback rules: visible deletes immediately show the adopted next live tab when one exists, while hidden deletes keep the UI hidden and only update active selection.
- category re-registration stays mutable until that specific category gets its first attached tab; after first use, only metadata-identical re-registration is allowed.
- `attach_and_show(...)` rollback now explicitly clears failed-tab watchers, handle ownership, user terminal mappings, and any partial visibility before restoring the prior active/visible UI state.
- `ui/tabbar.lua` owns the tabbar row-generation/rendering path.
- Mapping parsing/application is centralized in `shared/keymaps.lua`; `app/setup.lua`, `ui/init.lua`, and `ui/tabbar.lua` no longer each maintain their own mapping normalization/application loops.
- `ui/init.lua` now drives terminal-backed show/hide/toggle/delete/layout behavior directly from UI-owned tab state and owns terminal-buffer mapping application/cleanup during attach/show/layout refresh and rollback paths.
- `terminal/service.lua` no longer registers UI categories or mutates UI watcher/runtime state directly; it creates raw handles and leaves all runtime ownership to `ui/init.lua`.
- Automated tests now run through vendored `mini.test` with repo-local `luacov` wiring:
  - `tests/scenarios.lua` defines the shared smoke-behavior scenario functions,
  - `tests/test_smoke.lua` ports the old smoke harness into isolated `mini.test` cases with shared reset helpers,
  - smoke coverage focuses on generic terminal runtime plus task form/storage behavior only,
  - `tests/coverage.lua` executes the same scenarios directly under `luacov` to produce deterministic coverage stats,
  - `.luacov` limits coverage reporting to loaded `lua/qck/**` files, excludes tests/vendor code, and writes outputs under `tests/.coverage/`,
  - `tests/minitest.lua` and `tests/coverage.lua` force separate `XDG_DATA_HOME` roots under `tests/.tmp/` so storage tests cannot mutate the user’s real `qck.json` or race each other,
  - `tests/smoke.lua` is deprecated and exists only as a forwarding shim to the new test runner.

## Commit & Pull Request Guidelines
- Commit messages should be short, imperative, and scoped (example: `add multi terminal management api`).
- Keep one logical change per commit.
- After committing any code chunk, update `AGENTS.md` to reflect the new current architecture/guidelines.
- For any commit that includes AI-generated code, the commit body must include exactly: `Commit generated by AI`.
- PRs should include:
  - what changed and why,
  - manual test steps executed,
  - screenshots/GIFs for UI/window behavior changes.
