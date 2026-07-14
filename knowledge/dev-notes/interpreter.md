---
type: dev-note
tags:
  - note
---

# In-World Fennel Interpreter Dialog: Implementation Plan

## Objective
- Add an interactive Fennel interpreter widget/dialog that runs code inside the app process (same runtime context as remote control).
- Open this dialog from `normal-state` when the backquote key is pressed.
- Reuse existing UI/layout/state patterns (`DefaultDialog`, `Scene.add-panel-child`, `Input`, `ListView`, focus/input routing).

## Current Architecture Findings
- `assets/lua/normal-state.fnl` owns non-text-mode key handling and is the right place to add a new global shortcut in normal mode.
- `assets/lua/scene.fnl` `add-panel-child`/`remove-panel-child` already manage dialog lifecycle and cleanup via `on-close`.
- Dialog composition should follow `DefaultDialog` + content widget builder (see `assets/lua/launchables-helpers.fnl` terminal dialog).
- Input routing uses `assets/lua/input-state-router.fnl` with a single active input and state switching (`normal`/`text`/`insert`).
- Existing Fennel eval path is in `assets/lua/remote-control.fnl` using:
  - `pcall fennel.eval source {:env _G}`
  - `fennel.view` formatting for non-string values.

## Recommended Design

### 1) New reusable evaluator utility
- Add `assets/lua/fennel-evaluator.fnl` to centralize:
  - `eval-source(source)` -> `{ :ok bool :result any }`
  - `format-result(value)` (nil/string/other via `fennel.view`)
  - `format-error(value)` (stringify safe)
- Refactor `assets/lua/remote-control.fnl` to consume this module instead of local duplicated helpers.
- Benefit: identical semantics between remote-control and in-world interpreter, lower drift risk.

### 2) New interpreter view widget
- Add `assets/lua/fennel-interpreter-view.fnl`.
- Compose with existing widgets:
  - Top: multiline `Input` for source entry (e.g. 6-10 lines visible).
  - Middle/Bottom: output/history area via `ListView` (or `Text` buffer if list complexity is unnecessary).
  - Action row: `Run`, `Clear Output`, maybe `Clear Input`.
- Behavior:
  - On `Run`, evaluate current input with evaluator module.
  - Append transcript entries (`> code`, `< result` or `! error`) to output list.
  - Keep history bounded (configurable max entries, e.g. 200) to avoid unbounded memory growth.
  - Keep focus on input after run for iterative use.
- Runtime context:
  - Execute with `{:env _G}` to match remote-control behavior and support direct app inspection/manipulation.

### 3) New dialog builder helper
- Extend `assets/lua/launchables-helpers.fnl` with `make-fennel-interpreter-dialog`.
- Pattern should mirror `make-terminal-dialog`:
  - `DefaultDialog` title: `"Fennel Interpreter"`.
  - Wrap child in `Padding` and `Sized` for stable in-world dimensions.
  - Provide stable `:name`/`:focus-name` for focus and tests.

### 4) Scene-level singleton management
- Add a small helper in `normal-state` to open/toggle a single instance:
  - If already open, close/remove it.
  - If closed, create via `scene:add-panel-child`.
- Store pointer in app state, e.g. `app.fennel-interpreter-dialog`.
- Ensure pointer is nulled on dialog close (through `builder-options.on-close`) and when removed externally.
- This avoids stacking multiple interpreter dialogs from repeated key presses.

### 5) Keybinding in normal-state
- In `assets/lua/normal-state.fnl`, add backquote key branch before fallback to `base-on-key-down`.
- Handle only in `normal-state` as requested.
- Guardrails:
  - If an active input is currently attached, do not force-open (avoid surprising interruption of text editing).
  - Return `true` only when shortcut is handled.

### 6) Optional launcher/control-panel integration (follow-up)
- Optional: add launchable entry `assets/lua/launchables/fennel-interpreter.fnl`.
- Optional: add HUD control-panel button/icon.
- Not required for this request (shortcut-triggered dialog), but low-cost discoverability improvement.

## Test Plan

### Unit tests
- Update `assets/lua/tests/test-states.fnl`:
  - New test: backquote in normal-state opens interpreter dialog.
  - New test: second backquote closes existing interpreter dialog (if toggled behavior chosen).
  - Ensure key is swallowed when handled (does not reach first-person controls).
- Add `assets/lua/tests/test-fennel-interpreter-view.fnl`:
  - Evaluates expression and appends formatted result.
  - Errors are captured and shown in output.
  - Output clear action works.
  - History cap enforcement works.
- Update `assets/lua/tests/test-remote-control.fnl` only if evaluator refactor changes interface expectations.
- Register new test module in `assets/lua/tests/fast.fnl`.

### Manual verification
- Run:
  - `SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test`
- In app:
  - Press backquote in normal-state -> dialog appears in scene.
  - Execute sample code:
    - `(+ 1 2 3)`
    - `app.scene`
    - `(error "boom")`
  - Confirm results/errors render, focus remains usable, and close action fully cleans up.

## Implementation Sequence
1. Add `fennel-evaluator.fnl`.
2. Refactor `remote-control.fnl` to use evaluator.
3. Implement `fennel-interpreter-view.fnl`.
4. Add dialog helper in `launchables-helpers.fnl`.
5. Wire backquote handling + dialog lifecycle in `normal-state.fnl`.
6. Add/adjust tests (`test-fennel-interpreter-view.fnl`, `test-states.fnl`, `fast.fnl` registration).
7. Run test suite and fix regressions.

## Risks and Mitigations
- Risk: keycode mismatch for backquote across SDL/event payload.
  - Mitigation: confirm actual key value in this codebase before final binding.
- Risk: eval side effects destabilize app state.
  - Mitigation: document that interpreter executes in `_G` intentionally; keep explicit transcript and error reporting.
- Risk: focus/input-state interactions become sticky after close.
  - Mitigation: ensure `drop` disconnects input/focus listeners and `on-close` clears app pointer.

## Open Questions (need confirmation before implementation)
1. Backquote behavior: should it **toggle** open/close, or always open and keep existing instance if already open?
2. Execution trigger: is `Run` button sufficient initially, or do you want keyboard execution in MVP (for example Ctrl+Enter)?
3. Scope safety: should evaluator run with full `_G` (same as remote-control), or with a restricted environment for user-facing safety?


## See also

- [[kernel-system]]
