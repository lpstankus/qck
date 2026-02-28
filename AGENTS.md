# Repository Guidelines

## Project Structure & Module Organization
This repository is a Neovim plugin written in Lua.

- `lua/qck/init.lua`: public plugin API (`setup`, `new`, `run`, `build`, `open_builder`, `toggle_builder`, `kill_builder`, `set_builder_cmd`, `reset_builder_cmd`, `open`, `close`, `toggle`, `cycle_next`, `cycle_prev`, `switch_focus`).
- `lua/qck/builders.lua`: builder registry and orchestration (builder-type lifecycle, one-instance-per-type enforcement, effective command resolution).
- `lua/qck/storage.lua`: workspace-persistent storage for builder command overrides.
- `lua/qck/state.lua`: terminal registry and current-id/cycling state plus terminal record/window validity helpers.
- `lua/qck/terminal.lua`: terminal lifecycle orchestration over `snacks.terminal`.
- `lua/qck/tabbar.lua`: floating vertical tab bar that renders live terminal IDs.
- `LICENSE`: project license.

Keep new runtime code under `lua/qck/`. `init.lua` should remain the public entrypoint; internal behavior should be split by responsibility across focused modules.

## Build, Test, and Development Commands
There is no build system or package manifest. Use Neovim headless/manual checks:

- `nvim --headless --clean +"set rtp+=." +"lua require('qck')" +qa`  
  Verifies plugin load and runtime syntax (requires `snacks.nvim` on `runtimepath`).
- `nvim --headless --clean +"set rtp+=/path/to/snacks.nvim" +"set rtp+=." +"lua require('qck')"`  
  Verifies behavior with Snacks dependency on `runtimepath`.
- `luac -p lua/qck/*.lua`  
  Fast syntax check for all Lua modules.
- `nvim --clean +"set rtp+=."`  
  Opens an interactive clean session for manual testing.

## Coding Style & Naming Conventions
- Language: Lua (Neovim API via `vim.*`).
- Indentation: 2 spaces, no tabs.
- Prefer `local` functions/state; expose only intentional public API on `qck`.
- Use `snake_case` for functions/locals (`cycle_next`, `current_id`).
- Keep window/terminal side effects centralized and explicit.

## Testing Guidelines
Automated tests are not configured yet. Validate changes with:

1. Headless load check.
2. Manual workflow checks: `new`, `run`, `open`, `close`, `toggle`, `cycle_next`, `cycle_prev`.
   - `setup({ mappings = ... })` should apply mappings buffer-locally to qck terminal buffers (normal and terminal modes) and the qck tabbar buffer (normal mode).
3. Builder workflow checks:
   - `setup({ builders = { compilation = ..., server = ... } })` should register builder types,
   - `build("type")` should open an existing running instance for that builder type,
   - `build("type", { force_new = true })` should restart only that builder type,
   - only one running terminal instance per builder type should exist,
   - multiple different builder types should run concurrently.
4. Multi-terminal visibility checks:
   - creating/opening a different terminal should hide the previously visible terminal window,
   - `toggle` should affect only the current terminal visibility,
   - moving focus to a non-qck window (for example `<C-w>h`) should hide qck terminal and tabbar windows.
5. Tab bar checks:
   - opens/closes with the visible terminal window,
   - closes when the terminal window is closed manually (for example `:q`),
   - closing the tabbar window manually (for example `:q`) should hide the current terminal window,
   - pressing `<Esc>` in the tabbar focuses the current terminal window,
   - pressing `K`/`J` in the tabbar should move the selected terminal up/down within its own group (`L*` or `T*`),
   - `L*`/`T*` labels should stay with the same terminal when rows are reordered,
   - creating a new terminal should assign the lowest missing label number within its group for the current session,
   - current terminal line uses full-row reverse highlight.
6. Persistence checks:
   - `set_builder_cmd("type", cmd)` should persist command override per workspace cwd,
   - `set_builder_cmd("type", cmd, { temp = true })` should be session-only,
   - `reset_builder_cmd("type")` should clear temp override first, then persisted override.
7. Terminal exit checks (`exit`, `exit 1`) to verify close/error behavior.
8. Autoscroll checks for long-running/builder terminals:
   - output should follow when cursor is near bottom or terminal window is unfocused,
   - output should not force-scroll when user is inspecting older lines away from bottom.

When tests are added, place them under `tests/` and document the test runner here.

## Current Architecture Findings
- `snacks.nvim` is required at runtime; plugin load should fail early if unavailable.
- Shared validation helpers were removed from a separate module; helper logic now lives with owning modules:
  - `state.lua`: record/window validity checks,
  - `init.lua`: API input validation and notifications,
  - `terminal.lua`: Snacks and terminal-handle safety checks.
- Builder definitions are configured via `qck.setup({ builders = ... })` and normalized/validated in `init.lua`.
- Builder orchestration lives in `builders.lua` and keeps `init.lua` as a thin public API facade.
- Workspace persistence lives in `storage.lua` (`stdpath("data") .. "/qck.json"`) and currently stores per-workspace builder command overrides.
- Tab bar lifecycle is synchronized from `terminal.lua` and reinforced by a `WinClosed` autocmd watcher in `tabbar.lua`.
- When switching terminals, hiding the previous window (`toggle`) is safer than closing it (`close`), because closing may wipe the buffer and terminate the terminal job.
- `noautocmd` is valid when creating the tab bar float (`nvim_open_win`), but must not be passed to `nvim_win_set_config` for an existing window.
- `qck.new(opts)` currently accepts an optional table, but terminal title customization is not used.
- State now exposes partition and ordering helpers for mixed terminal kinds:
  - `partitioned_ids()` returns three lists: `all_ids`, `long_running_ids`, `default_ids`,
  - `ordered_ids()` returns long-running ids first, then default ids, preserving per-kind in-session manual order.
  - `move_id_within_kind(id, direction)` reorders a terminal within its own kind (`long_running` or `default`) for the current session.
  - `get_group_label_id(id)` returns a stable per-kind generation label id (`T#`/`L#`) for the terminal in the current session.
- State now exposes builder helpers:
  - `find_terminal_id_by_builder_type(builder_type)` returns the running terminal id for a builder type,
  - `get_builder_type(id)` returns the builder type metadata for a terminal id when present.
- `terminal.create(id, opts)` now accepts terminal kind metadata (`default` or `long_running`) and optional command input for command-driven terminal startup.
- Long-running terminals are marked with `rec.meta.kind = "long_running"` and created with `auto_close = false` to preserve output after process exit.
- `terminal.run(id, cmd, opts?)` creates long-running terminals and rejects internal-id collisions to avoid replacing existing terminal records.
- `qck.run(cmd, opts?)` is the public command-driven API for long-running tasks; it validates command shape (`string` or string list) and optional `opts.id`.
- Builder terminals include `rec.meta.builder_type`; this metadata is used to enforce one running instance per builder type while allowing concurrent runs across different types.
- `qck.build(builder_type, opts?)` opens the existing running builder instance by default; restart requires `{ force_new = true }`.
- Builder command resolution precedence is: temporary override (`set_builder_cmd(..., { temp = true })`) > persisted workspace override > setup default.
- Calling `qck.setup(...)` replaces builder definitions and resets all temporary (`temp = true`) builder command overrides for the current session.
- `terminal.lua` now manages per-terminal buffer hook groups to keep lifecycle cleanup centralized when terminals are deleted/wiped.
- Autoscroll for long-running/builder terminals is enabled by default and follows output only when near bottom or unfocused.
- Builder `title` in `setup({ builders = ... })` and `qck.run(..., { title = ... })` are currently accepted/validated but reserved for future UI usage.
- Tabbar rendering now decouples visual ids from internal ids:
  - long-running rows are labeled `L1`, `L2`, ... from per-group generation labels,
  - default rows are labeled `T1`, `T2`, ... from per-group generation labels,
  - generation labels are stable per terminal instance and do not change when rows are reordered,
  - label numbers reuse the lowest missing value per group when terminals are deleted and new ones are created,
  - row actions (`<CR>`, `dd`) resolve labels back to internal terminal ids.
- Tabbar supports manual reordering in normal mode with `K` (move selected terminal up) and `J` (move selected terminal down), scoped to the selected terminal kind group.
- User mappings configured via `qck.setup({ mappings = ... })` are now applied to both terminal buffers and the tabbar buffer.
- Tabbar cursor placement now lands on the centered row label's numeric part (or first non-space character when no number is present).
- Tabbar includes a built-in normal-mode `<Esc>` mapping that returns focus to the current terminal window.
- Tabbar now watches its own `WinClosed` event; manual tabbar closes trigger hiding the current terminal window while internal tabbar closes suppress this action.
- `init.lua` wires tabbar actions (`open`, `delete`, `move_up`, `move_down`, `close_current`, `focus_current`) to terminal behavior; `close_current` delegates to `terminal.hide_current_if_open()` to avoid wiping terminal buffers/jobs.
- `init.lua` now installs a global focus watcher (`WinEnter`, `BufEnter`, `TabEnter`) that hides qck terminal and tabbar windows when focus leaves both qck windows (for example navigating with `<C-w>h`).
- Visual labels are UI-only; public APIs (`open`, `close`, `toggle`, `run`) continue to operate on internal numeric ids.

## Commit & Pull Request Guidelines
- Commit messages should be short, imperative, and scoped (example: `add multi terminal management api`).
- Keep one logical change per commit.
- After committing any code chunk, update `AGENTS.md` to reflect the new current architecture/guidelines.
- For any commit that includes AI-generated code, the commit body must include exactly: `Commit generated by AI`.
- PRs should include:
  - what changed and why,
  - manual test steps executed,
  - screenshots/GIFs for UI/window behavior changes.
