# Repository Guidelines

## Project Structure & Module Organization
This repository is a Neovim plugin written in Lua.

- `lua/qck/init.lua`: public plugin API (`setup`, `clear_storage`, `new`, `new_task`, `open`, `close`, `toggle`, `cycle_next`, `cycle_prev`, `switch_focus`).
- `lua/qck/shared/autocmd.lua`: shared plugin autocmd wrapper exposing a single `qck` augroup.
- `lua/qck/shared/cmd.lua`: shared command normalization/cloning/validation helpers (`string` or string-list commands).
- `lua/qck/shared/mappings.lua`: shared mapping state helpers for tracking/removing user-configured buffer mappings.
- `lua/qck/shared/notify.lua`: shared `QCK:` notification helper.
- `lua/qck/shared/types.lua`: shared EmmyLua type aliases/classes.
- `lua/qck/terminal/service.lua`: terminal lifecycle orchestration over `snacks.terminal`.
- `lua/qck/terminal/state.lua`: terminal registry and current-id/cycling state plus terminal record/window validity helpers.
- `lua/qck/terminal/layout.lua`: shared floating terminal/tabbar layout calculations.
- `lua/qck/terminal/tabbar.lua`: floating vertical tab bar that renders live terminal ids.
- `lua/qck/tasks/storage.lua`: workspace-persistent storage for workspace-created task definitions.
- `lua/qck/tasks/form.lua`: floating task-creation form UI (name/cmd fields, Tab cycling, overwrite confirmation, workspace save).
- `lua/qck/app/setup.lua`: setup-time wiring for Snacks bootstrapping, mapping parsing, and storage load.
- `lua/qck/app/targets.lua`: shared API target-id validation and fallback resolution for `open(id?)` / `close(id?)`.
- `lua/qck/app/focus.lua`: global qck/tabbar focus and resize autocmd wiring.
- `tests/mock_snacks.lua`: deterministic Snacks terminal mock for headless `mini.test` coverage/integration runs.
- `tests/helpers.lua`: shared `mini.test` helper utilities for storage seeding, environment reset, and repeated UI/layout assertions.
- `tests/test_smoke.lua`: `mini.test` suite covering the current smoke-test behavior in isolated cases.
- `tests/scenarios.lua`: shared smoke-behavior scenario functions reused by both the `mini.test` suite and the coverage runner.
- `tests/minitest.lua`: headless `mini.test` bootstrap/runner with vendored dependency path setup.
- `tests/coverage.lua`: headless scenario runner that executes the same smoke assertions under vendored `luacov`.
- `tests/luacov_report.lua`: headless coverage-report generator using vendored `luacov`.
- `tests/smoke.lua`: deprecated compatibility shim that warns and forwards to the `mini.test` runner.
- `tests/vendor/`: vendored test-only dependencies (`mini.test` and `luacov`).
- `LICENSE`: project license.

Keep new runtime code under `lua/qck/`. `init.lua` should remain the public entrypoint; internal behavior should be split by package responsibility across `shared/`, `terminal/`, `tasks/`, and `app/`.

## Build, Test, and Development Commands
There is no build system or package manifest. Use Neovim headless/manual checks:

- `nvim --headless --clean +"set rtp+=." +"lua require('qck')" +qa`
  Verifies plugin load and runtime syntax (requires `snacks.nvim` on `runtimepath`).
- `nvim --headless --clean +"set rtp+=/path/to/snacks.nvim" +"set rtp+=." +"lua require('qck')"`
  Verifies behavior with Snacks dependency on `runtimepath`.
- `luac -p $(rg --files lua/qck -g '*.lua')`
  Fast syntax check for all Lua modules, including packaged subdirectories.
- `nvim --headless --clean -u NONE +"lua dofile('tests/minitest.lua')"`
  Runs the mocked `mini.test` suite headlessly with vendored `mini.test`.
- `nvim --headless --clean -u NONE +"lua dofile('tests/coverage.lua')"`
  Runs the same smoke-behavior scenarios under vendored `luacov` to collect line coverage stats.
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
5. Manual workflow checks: `new`, `open`, `close`, `toggle`, `cycle_next`, `cycle_prev`, `clear_storage`.
6. Multi-terminal visibility checks:
   - creating/opening a different terminal should hide the previously visible terminal window,
   - `toggle` should affect only the current terminal visibility,
   - moving focus to a non-qck window (for example `<C-w>h`) should hide qck terminal and tabbar windows,
   - terminal width should shrink by the tabbar width and shift right so the combined terminal+tabbar footprint fills the bordered editor footprint,
   - resizing from small -> large and from large -> small should preserve qck terminal/tabbar geometry when the resized terminal is hidden and reopened,
   - resize regression coverage should simulate the observed failure mode where the terminal temporarily expands beyond the allowed bordered editor footprint and covers the tabbar area before deferred qck layout repair runs.
7. Tab bar checks:
   - opens/closes with the visible terminal window,
   - closes when the terminal window is closed manually (for example `:q`),
   - closing the tabbar window manually (for example `:q`) should hide the current terminal window,
   - pressing `<Esc>` in the tabbar focuses the current terminal window,
   - pressing `K`/`J` in the tabbar should move the selected terminal up/down within the single terminal list,
   - `T*` labels should stay with the same terminal when rows are reordered,
   - creating a new terminal should assign the lowest missing `T*` label number for the current session,
   - current terminal line uses full-row reverse highlight.
8. Storage behavior checks:
   - unsupported or invalid schema should fail load and warn users,
   - `clear_storage()` should clear persisted data for current workspace,
   - no implicit storage reset should happen on failed load.
9. Terminal exit checks (`exit`, `exit 1`) to verify close/error behavior.
10. Autoscroll checks for terminals created with `auto_scroll = true`:
    - output should follow when cursor is near bottom or terminal window is unfocused,
    - output should not force-scroll when user is inspecting older lines away from bottom.
11. Task form checks:
    - `new_task()` opens a floating form with task name/command fields,
    - calling `new_task()` while the form is already open should focus/reuse the same window,
    - form scaffold lines (description/prefix/help) should be rendered and preserved,
    - `Tab`/`Shift-Tab` cycles fields in both normal and insert modes,
    - first save on duplicate name warns and keeps form open,
    - validation errors (for example empty task name) keep the form open and clear pending duplicate overwrite confirmation,
    - after changing form contents following a duplicate warning, overwrite must require confirmation again,
    - second save on the same duplicate name overwrites and closes form,
    - successful save persists task command for the current workspace only.
12. Storage-only task checks:
    - storage load/save round-trips normalized workspace task commands,
    - workspace task data remains isolated per working directory,
    - `reset_task_cmd()` removes only the targeted workspace task entry.

Additional tests should be placed under `tests/` and documented in this section.

## Current Architecture Findings
- `snacks.nvim` is required at runtime; plugin load should fail early if unavailable.
- Package boundaries are:
  - `shared/`: leaf utilities only, with no imports from `terminal/`, `tasks/`, or `app/`,
  - `terminal/`: terminal state, layout, tabbar, and terminal lifecycle,
  - `tasks/`: workspace-persistent task storage and the floating task form UI,
  - `app/`: top-level setup/focus/target orchestration used by `init.lua`.
- State validity checks guard terminal-handle method calls with `pcall`, so stale/invalid handle behavior cannot break prune/cycle paths.
- `terminal.create(...)` closes partially opened terminal handles when handle initialization fails, preventing leaked untracked terminal resources.
- Workspace persistence lives in `tasks/storage.lua` (`stdpath("data") .. "/qck.json"`) and stores only per-workspace saved task commands created through `qck.new_task()`.
- `storage.load()` / `storage.save()` return `(ok, err)` and track `storage.last_error`, so callers can report concrete persistence failure details.
- Storage loading is fail-fast on unsupported/invalid schema and does not mutate files automatically.
- `qck.clear_storage()` is the explicit user-triggered storage reset entrypoint for current workspace state.
- Shared EmmyLua type aliases/classes live in `lua/qck/shared/types.lua`, and module annotations use these types to tighten internal contracts for LuaLS.
- `lua/qck/init.lua` is limited to the public API surface plus imports; app-level orchestration lives under `lua/qck/app/`.
- Command normalization/cloning/validation is centralized in `lua/qck/shared/cmd.lua` and reused by `tasks/form.lua` and `tasks/storage.lua`.
- Shared `QCK:` notifications are centralized in `lua/qck/shared/notify.lua` and reused by `init.lua`, `tasks/form.lua`, `terminal/service.lua`, and `app/`.
- Mapping-state diff/cleanup helpers are centralized in `lua/qck/shared/mappings.lua` and reused by both terminal and tabbar mapping application paths.
- Tab bar lifecycle is synchronized from `terminal/service.lua` and reinforced by a `WinClosed` autocmd watcher in `terminal/tabbar.lua`.
- Floating window geometry is centralized in `lua/qck/terminal/layout.lua`; terminal and tabbar floats share one width/column calculation so the tabbar consumes space inside the original terminal footprint instead of extending it.
- Shared terminal/tabbar layout reserves a two-column gap between the tabbar and terminal so both float borders remain visually distinct inside the original terminal footprint.
- Shared terminal/tabbar layout uses `relative = "editor"` and a full-editor bordered footprint while keeping the tabbar inside that total size budget.
- All plugin autocmds share a single `qck` augroup via `shared/autocmd.lua`; modules track and delete autocmd ids for targeted cleanup.
- When switching terminals, hiding the previous window (`toggle`) is safer than closing it (`close`), because closing may wipe the buffer and terminate the terminal job.
- `noautocmd` is valid when creating the tab bar float (`nvim_open_win`), but must not be passed to `nvim_win_set_config` for an existing window.
- `qck.new(_opts)` keeps a compatibility parameter but no longer validates/uses it internally.
- State exposes a single ordered terminal list for cycling and tabbar rendering:
  - `ordered_ids()` preserves in-session manual order across all live terminals,
  - `move_id(id, direction)` reorders a terminal within that single list,
  - `get_label_id(id)` returns a stable session label id used for `T#` tabbar rows.
- Terminal runtime is fully generic: `terminal.create(id, opts)` accepts optional command input plus generic terminal options and does not distinguish task terminals from ad hoc terminals.
- Task support is intentionally limited to `qck.new_task()`, `tasks/storage.lua`, and `qck.clear_storage()`; there is no task execution, hydration, override, or task-linked terminal runtime.
- `qck.new_task()` opens `tasks/form.lua` floating UI for creating workspace-scoped tasks; form saves trimmed task commands into workspace storage.
- Task form duplicate protection is explicit two-step overwrite: first submit on an existing task warns, second submit with the same name confirms overwrite.
- `tasks/form.lua` keeps runtime UI state in a single local state table (`bufnr`/`winid`/selection/pending overwrite/autocmd ids) instead of scattered module globals.
- Task form submit sanitization preserves support for legacy inline labels (`Name: ...` / `Command: ...`) by normalizing to current prefixed scaffold rows before validation/save.
- `tasks/form.lua` writes workspace task commands directly through `tasks/storage.lua` and checks duplicates against persisted workspace data.
- `terminal/service.lua` manages per-terminal buffer hook groups to keep lifecycle cleanup centralized when terminals are deleted/wiped.
- Autoscroll is opt-in per terminal via `opts.auto_scroll` and follows output only when near bottom or unfocused.
- Autoscroll output tracking is attached with `nvim_buf_attach(..., { on_lines = ... })` instead of `TextChanged` autocmds, improving long-running/background output handling.
- Tabbar rendering decouples visual ids from internal ids:
  - rows are labeled `T1`, `T2`, ... from stable session label ids,
  - label numbers reuse the lowest missing value when terminals are deleted and new ones are created,
  - row actions (`<CR>`, `dd`) resolve labels back to internal terminal ids.
- Tabbar supports manual reordering in normal mode with `K` (move selected terminal up) and `J` (move selected terminal down) within the single terminal list.
- User mappings configured via `qck.setup({ mappings = ... })` are normalized in `app/setup.lua` and applied to both terminal buffers and the tabbar buffer:
  - legacy entries (`lhs = rhs`) default to terminal `n`+`t`,
  - mapping specs (`lhs = { rhs = ..., mode = ... }`) allow terminal-mode scoping (`n`, `t`, or both),
  - tabbar user mappings remain normal-mode-only.
- Tabbar cursor placement lands on the centered row label's numeric part (or first non-space character when no number is present).
- Tabbar includes a built-in normal-mode `<Esc>` mapping that returns focus to the current terminal window.
- Tabbar watches its own `WinClosed` event; manual tabbar closes trigger hiding the current terminal window while internal tabbar closes suppress this action.
- `app/focus.lua` wires tabbar actions (`open`, `delete`, `move_up`, `move_down`, `close_current`, `focus_current`) to terminal behavior; `close_current` delegates to `terminal.hide_current_if_open()` to avoid wiping terminal buffers/jobs.
- `app/focus.lua` installs a global focus watcher (`WinEnter`, `BufEnter`, `TabEnter`) that hides qck terminal and tabbar windows when focus leaves both qck windows (for example navigating with `<C-w>h`).
- `app/focus.lua` installs a deferred `VimResized` watcher that reapplies the shared qck terminal/tabbar layout for the current visible terminal after resize-driven float updates settle.
- `app/targets.lua` resolves `open(id?)` / `close(id?)` target ids through shared helpers to avoid duplicated id-validation and fallback logic.
- Visual labels are UI-only; public APIs (`open`, `close`, `toggle`) operate on internal numeric ids.
- `terminal.open(id, opts?)` and `terminal.create(id, opts?)` accept internal `opts.preserve_mode` and restore normal mode after switching/creating when requested.
- `terminal.refresh_current_layout()` reapplies shared geometry to the current visible qck terminal and resyncs the tabbar; hidden terminals are laid out when reopened.
- `qck.cycle_next()` / `qck.cycle_prev()` request mode preservation; `qck.new()` requests it only when a qck terminal window is currently open.
- Automated tests now run through vendored `mini.test` with repo-local `luacov` wiring:
  - `tests/scenarios.lua` defines the shared smoke-behavior scenario functions,
  - `tests/test_smoke.lua` ports the old smoke harness into isolated `mini.test` cases with shared reset helpers,
  - smoke coverage focuses on generic terminal runtime plus task form/storage behavior only,
  - `tests/coverage.lua` executes the same scenarios directly under `luacov` to produce deterministic coverage stats,
  - `.luacov` limits coverage reporting to loaded `lua/qck/**` files, excludes tests/vendor code, and writes outputs under `tests/.coverage/`,
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
