# Lazy Text Buffer Virtual Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a file-backed lazy text buffer and `VirtualInput` widget that can view and edit arbitrarily large text files without loading whole files into memory.

**Architecture:** Add a new lazy text stack beside the existing whole-buffer `Input`/`InputModel`. Native filesystem primitives provide file tokens, bounded raw range reads, and conditional atomic replacement; Fennel `LazyTextSource` and `LazyTextBuffer` provide piece-table editing, sparse line indexing, and bounded viewport snapshots; `VirtualInput` renders only visible rows and powers the graph filesystem file viewer.

**Tech Stack:** C++17 filesystem bindings in `src/lua_fs.cpp`; Space Fennel modules under `assets/lua`; widgets `Text`, `Rectangle`, `Layout`, `InputState`, `Button`, and `Flex`; Fennel tests under `assets/lua/tests`; graph filesystem viewer modules under `assets/lua/graph`.

## Global Constraints

- Provide a `VirtualInput` widget for file-scale text viewing and editing.
- Keep existing `Input` and `InputModel` behavior compatible for small controls.
- Support arbitrarily large files by bounding source reads, visible rendering, and cached indexing work.
- Represent edits without loading unchanged file content into memory.
- Make the filesystem file viewer use `VirtualInput` for internal editing.
- Save safely: detect external file changes before writing and avoid blind overwrite.
- No syntax highlighting in this iteration.
- No undo/redo history in this iteration.
- No multi-cursor editing.
- No Vim/Neovim modal command parity.
- No collaborative editing or CRDTs.
- No binary/hex editing.
- No search/replace over unloaded whole files.
- No retained backup-file policy beyond temporary files needed for atomic save.
- Existing `InputModel` stores whole text as codepoints and must not be used for file-scale buffers.
- Existing `Text` may render visible slices, but no new code may pass whole large files to `Text`.
- `ScrollView`/`ScrollArea` clip and scroll only; do not depend on them for child virtualization.
- `VirtualInput` builders must assert required context.
- Unsupported operations must fail loudly rather than no-op.
- The editor must not fall back to whole-file reads when lazy indexing is incomplete.
- For Fennel code use `local`, factory functions, and explicit final object literals.
- For Fennel/UI changes run project-native compile checks first, constraints second, and focused tests third.
- Because this changes C++ bindings, file operations, graph file interactions, and active text input behavior, final validation must include `make build` and the broader test suite.

---

## File Structure

- `src/lua_fs.cpp`: add raw range reads, file identity tokens, and conditional atomic replacement.
- `assets/lua/lazy-text-source.fnl`: source adapter for file-backed bounded reads and baseline tokens.
- `assets/lua/lazy-text-buffer.fnl`: piece-table document model, sparse line index, edits, selection, and save.
- `assets/lua/virtual-input.fnl`: file-scale text widget that renders bounded viewport rows and routes input to `LazyTextBuffer`.
- `assets/lua/graph/nodes/fs-file-viewer.fnl`: own a lazy source/buffer for each file viewer node.
- `assets/lua/graph/view/views/fs-file-viewer.fnl`: replace chunk display with `VirtualInput`, save/status controls, and external editor affordance.
- `assets/lua/tests/test-lazy-text-buffer.fnl`: filesystem primitive and lazy buffer tests.
- `assets/lua/tests/test-virtual-input.fnl`: widget behavior tests.
- `assets/lua/tests/test-fs-file-viewer.fnl`: graph viewer integration tests.
- `assets/lua/tests/fast.fnl`: register new focused test modules.
- `docs/dev/features/lazy-text-buffer-virtual-input.md`: developer documentation.
- `docs/dev/features/graph-filesystem-file-interactions.md`: update viewer documentation from read-only chunks to editable `VirtualInput`.
- `docs/dev/features/index.md`: add a feature-page link if this index exists and is used for similar pages.

---

### Task 1: Native file source and conditional atomic save primitives

**Files:**
- Modify: `src/lua_fs.cpp`
- Modify: `assets/lua/tests/test-fs.fnl`

**Interfaces:**
- Consumes: existing `fs.stat`, `fs.absolute`, `fs.join-path`, `fs.write-file`, and `fs.read-file` test helpers.
- Produces:
  - `fs.file-token(path: string) -> table`
  - `fs.read-byte-range(path: string, offset: number, max-bytes: number) -> table`
  - `fs.atomic-replace-if-current(path: string, segments: table[], expected-token: table, opts?: table) -> table`

- [ ] **Step 1: Add failing tests for file tokens and range reads**

  In `assets/lua/tests/test-fs.fnl`, add tests named:

  ```fennel
  "fs file-token reports regular file identity"
  "fs read-byte-range returns bounded raw bytes"
  "fs read-byte-range rejects invalid arguments"
  ```

  Required assertions:

  ```fennel
  (local token (fs.file-token file))
  (assert (= token.path (fs.absolute file)))
  (assert token.exists)
  (assert token.is-file)
  (assert (= token.size 6))
  (assert token.modified)
  (assert token.permissions)

  (local range (fs.read-byte-range file 2 3))
  (assert (= range.offset 2))
  (assert (= range.next-offset 5))
  (assert (= range.size 6))
  (assert (= range.bytes-read 3))
  (assert (= range.bytes "cde"))
  (assert (not range.eof))
  ```

  Invalid argument coverage must assert explicit failures for empty path, negative offset, and `max-bytes <= 0` with error text containing `fs.read_byte_range`.

- [ ] **Step 2: Add failing tests for conditional atomic replacement**

  Add tests named:

  ```fennel
  "fs atomic-replace-if-current writes text and source segments"
  "fs atomic-replace-if-current rejects stale token"
  "fs atomic-replace-if-current rejects malformed segments"
  ```

  Required successful-save assertion:

  ```fennel
  (local token (fs.file-token file))
  (local result
    (fs.atomic-replace-if-current
      file
      [{:source-path file :offset 0 :bytes 2}
       {:text "XY"}
       {:source-path file :offset 4 :bytes 2}]
      token))
  (assert result.saved)
  (assert (= result.path (fs.absolute file)))
  (assert (= (fs.read-file file) "abXYef"))
  (assert result.token)
  (assert (= result.token.size 6))
  ```

  Stale-token coverage must capture a token, mutate the file with `fs.write-file`, call `fs.atomic-replace-if-current`, and assert failure text contains `fs.atomic_replace_if_current: file changed since token`.

  Segment validation coverage must reject negative offsets, negative byte counts, missing `source-path`, and a segment that contains neither `text` nor `source-path` with error text containing `fs.atomic_replace_if_current`.

- [ ] **Step 3: Run validation and confirm the new tests fail**

  Run:

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-fs.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs:main
  ```

  Expected: compile and constraints pass; focused fs tests fail because the new bindings are missing.

- [ ] **Step 4: Implement `fs.file-token` in `src/lua_fs.cpp`**

  Requirements:

  - reject empty path with `fs.file_token: path must be non-empty`;
  - return normalized absolute `path`;
  - return `exists`, `is-file`, `size`, `modified`, and `permissions` fields;
  - use filesystem errors as explicit `sol::error` messages;
  - use stable primitive values only: strings, booleans, and numbers.

- [ ] **Step 5: Implement `fs.read-byte-range` in `src/lua_fs.cpp`**

  Requirements:

  - reject empty path, negative offset, and non-positive `max-bytes` with `fs.read_byte_range` messages;
  - cap each read to `262144` bytes;
  - use `std::ifstream` in binary mode, `seekg`, and bounded `read`;
  - return raw `bytes` without UTF-8 sanitization;
  - return `path`, `offset`, `next-offset`, `size`, `bytes-read`, and `eof`.

- [ ] **Step 6: Implement `fs.atomic-replace-if-current` in `src/lua_fs.cpp`**

  Requirements:

  - reject empty path with `fs.atomic_replace_if_current: path must be non-empty`;
  - compare current token fields `path`, `exists`, `is-file`, `size`, `modified`, and `permissions` to the expected token;
  - if the token differs, throw `fs.atomic_replace_if_current: file changed since token`;
  - accept segment forms `{:text string}` and `{:source-path string :offset number :bytes number}` only;
  - validate segment offsets and byte counts are non-negative;
  - stream source segments with bounded buffers and never load the whole source file;
  - write to a sibling temp path under the same parent directory;
  - preserve original permissions where possible;
  - atomically replace the target with filesystem rename;
  - on success return `{saved = true, path = absolute-path, token = fs.file-token(path)}`.

- [ ] **Step 7: Register bindings**

  Register exact names:

  ```cpp
  fs_table.set_function("file-token", &fs_file_token);
  fs_table.set_function("read-byte-range", &fs_read_byte_range);
  fs_table.set_function("atomic-replace-if-current", &fs_atomic_replace_if_current);
  ```

- [ ] **Step 8: Validate Task 1**

  Run the same commands from Step 3. Expected: all pass.

- [ ] **Step 9: Commit Task 1**

  ```bash
  git add src/lua_fs.cpp assets/lua/tests/test-fs.fnl
  git commit -m "feat(engine): add lazy file editing primitives"
  ```

---

### Task 2: Lazy text source and piece-table buffer core

**Files:**
- Create: `assets/lua/lazy-text-source.fnl`
- Create: `assets/lua/lazy-text-buffer.fnl`
- Create: `assets/lua/tests/test-lazy-text-buffer.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `fs.file-token`, `fs.read-byte-range`, and `fs.atomic-replace-if-current`.
- Produces:
  - `LazyTextSource.file(path: string, opts?: table) -> source`
  - `LazyTextBuffer(opts: {source: source, chunk-bytes?: number}) -> buffer`
  - `buffer:get-viewport(opts: {line: number, column: number, lines: number, columns: number}) -> snapshot`
  - `buffer:insert-text(text: string) -> boolean`
  - `buffer:delete-before-cursor() -> boolean`
  - `buffer:delete-at-cursor() -> boolean`
  - `buffer:move-caret-to-byte(byte: number) -> boolean`
  - `buffer:move-caret-to-line-column(line: number, column: number) -> boolean`
  - `buffer:scroll-lines(delta: number) -> boolean`
  - `buffer:set-selection(anchor-byte: number, active-byte: number) -> boolean`
  - `buffer:clear-selection() -> boolean`
  - `buffer:get-selected-text() -> string`
  - `buffer:save(opts?: table) -> table`

- [ ] **Step 1: Add failing lazy source tests**

  Create `assets/lua/tests/test-lazy-text-buffer.fnl` with tests named:

  ```fennel
  "lazy text source reads bounded byte ranges"
  "lazy text source records baseline token"
  ```

  Assertions must prove `source.path` is absolute, `source.baseline-token` is populated, `source:read-range 2 3` returns `cde`, and no method calls `fs.read-file`.

- [ ] **Step 2: Add failing viewport and lazy-read tests**

  Add tests named:

  ```fennel
  "lazy text buffer viewport reads only requested rows"
  "lazy text buffer indexes LF and CRLF across chunks"
  "lazy text buffer maps UTF-8 columns to byte offsets"
  ```

  Required assertions:

  ```fennel
  (local snapshot (buffer:get-viewport {:line 1 :column 0 :lines 2 :columns 20}))
  (assert (= (length snapshot.rows) 2))
  (assert (= (. snapshot.rows 1 :text) "line-1"))
  (assert (= (. snapshot.rows 2 :text) "line-2"))
  (assert (= snapshot.start-line 1))
  (assert (= snapshot.requested-lines 2))
  ```

  UTF-8 coverage must use text `aλ🙂z` and assert the row’s `column-byte-offsets` advances by the correct UTF-8 byte lengths.

- [ ] **Step 3: Add failing edit and selection tests**

  Add tests named:

  ```fennel
  "lazy text buffer inserts and deletes across piece boundaries"
  "lazy text buffer selection copies across original and added pieces"
  "lazy text buffer preserves invalid original bytes when untouched"
  ```

  Required edit assertions:

  ```fennel
  (buffer:move-caret-to-byte 3)
  (buffer:insert-text "XY")
  (assert buffer.dirty?)
  (buffer:delete-before-cursor)
  (local snapshot (buffer:get-viewport {:line 0 :column 0 :lines 1 :columns 20}))
  (assert (= (. snapshot.rows 1 :text) "abcXdef"))
  ```

  Selection coverage must select a range spanning original and added pieces and assert `get-selected-text` returns the composed text only for that range.

  Invalid-byte preservation must write bytes containing `255`, open the buffer, insert text elsewhere, save, and assert the raw invalid byte remains in the saved file.

- [ ] **Step 4: Add failing save tests**

  Add tests named:

  ```fennel
  "lazy text buffer save streams pieces through atomic replace"
  "lazy text buffer save reports external modification conflict"
  ```

  Required assertions: successful save clears `dirty?`, refreshes `source.baseline-token`, and writes the composed file; conflict leaves `dirty?` true and error/status text contains `file changed since token`.

- [ ] **Step 5: Register the test module**

  Add `:tests.test-lazy-text-buffer` to `assets/lua/tests/fast.fnl` near the other filesystem/editor tests.

- [ ] **Step 6: Verify tests fail before implementation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-lazy-text-buffer.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  ```

  Expected: compile or focused test fails because the lazy modules do not exist.

- [ ] **Step 7: Implement `assets/lua/lazy-text-source.fnl`**

  Requirements:

  - `LazyTextSource.file(path, opts)` returns a final literal source object;
  - store absolute `path`, `baseline-token`, `size`, and `chunk-bytes` defaulting to `65536`;
  - `source:read-range(offset, max-bytes)` delegates only to `fs.read-byte-range`;
  - `source:current-token()` delegates to `fs.file-token`;
  - `source:refresh-token()` updates baseline token and size;
  - no method may call `fs.read-file`.

- [ ] **Step 8: Implement `assets/lua/lazy-text-buffer.fnl` core**

  Requirements:

  - initialize pieces to one original span `{source :original, offset 0, bytes source.size}`;
  - store add-buffer as a string containing only inserted text;
  - positions are absolute composed-document byte offsets;
  - reject invalid UTF-8 inserted text with error text containing `LazyTextBuffer insert-text requires valid UTF-8`;
  - `insert-text`, `delete-before-cursor`, and `delete-at-cursor` update pieces, cursor byte, selection, dirty state, and line anchor invalidation;
  - source reads for viewport extraction must request bounded ranges only.

- [ ] **Step 9: Implement sparse line index and viewport snapshots**

  Requirements:

  - cache line anchors as `{line, byte}`;
  - scan forward from nearest cached anchor in bounded chunks;
  - support LF and CRLF newline byte lengths;
  - `get-viewport` returns `{start-line, start-column, requested-lines, requested-columns, rows}`;
  - each row has `{line, start-byte, end-byte, newline-bytes, text, codepoints, column-byte-offsets}`;
  - row text/codepoints are clipped to requested columns, not the whole document.

- [ ] **Step 10: Implement selection and save**

  Requirements:

  - `set-selection(anchor-byte, active-byte)` stores ordered byte endpoints and active direction;
  - `get-selected-text()` composes only selected spans;
  - `save()` converts pieces to segment tables and delegates to `fs.atomic-replace-if-current`;
  - successful save refreshes the source token, collapses pieces to a single original span, clears add buffer, and clears `dirty?`;
  - failed save keeps `dirty?` true and returns or raises explicit conflict/error status.

- [ ] **Step 11: Validate Task 2**

  Run the same commands from Step 6, now including `--file assets/lua/lazy-text-source.fnl --file assets/lua/lazy-text-buffer.fnl`. Expected: all pass.

- [ ] **Step 12: Commit Task 2**

  ```bash
  git add assets/lua/lazy-text-source.fnl assets/lua/lazy-text-buffer.fnl assets/lua/tests/test-lazy-text-buffer.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(ui): add lazy text buffer"
  ```

---

### Task 3: VirtualInput widget

**Files:**
- Create: `assets/lua/virtual-input.fnl`
- Create: `assets/lua/tests/test-virtual-input.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `LazyTextBuffer`, `Text`, `TextStyle`, `Rectangle`, `Layout`, `InputState`, and `widget-theme-utils`.
- Produces: `VirtualInput(opts: {buffer: table, line-count?: number, column-count?: number, focusable?: boolean, text-style?: table, on-change?: function, on-save?: function}) -> build(ctx) -> widget`.

- [ ] **Step 1: Add failing widget tests**

  Create `assets/lua/tests/test-virtual-input.fnl` with tests named:

  ```fennel
  "VirtualInput requires explicit build context"
  "VirtualInput renders only visible viewport rows"
  "VirtualInput caret navigation loads lazy rows"
  "VirtualInput inserts and deletes through lazy buffer"
  "VirtualInput copies selected text"
  "VirtualInput save reports success and conflict"
  "VirtualInput drop tears down owned children"
  ```

  Use a test context patterned after `test-input.fnl` and `test-fs-file-viewer.fnl` with stub text vectors, clickables, hoverables, and focus state.

- [ ] **Step 2: Register the test module**

  Add `:tests.test-virtual-input` to `assets/lua/tests/fast.fnl` near `:tests.test-lazy-text-buffer`.

- [ ] **Step 3: Verify tests fail before implementation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-virtual-input.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  ```

  Expected: compile or focused test fails because `virtual-input.fnl` does not exist.

- [ ] **Step 4: Implement bounded row rendering**

  Requirements:

  - builder asserts explicit `ctx`;
  - build exactly `line-count` row `Text` widgets plus caret/background rectangles;
  - each render refresh calls `buffer:get-viewport` and feeds only row text/codepoints to row widgets;
  - expose test handles `rows`, `caret`, `layout`, `buffer`, `save`, `copy-selection`, and `drop`;
  - no code path passes whole document content to `Text`.

- [ ] **Step 5: Implement input and navigation methods**

  Requirements:

  - methods `on-text-input`, `on-key-down`, `insert-text`, `delete-before-cursor`, `delete-at-cursor`, `move-caret`, `scroll-lines`, `copy-selection`, and `save` delegate to the buffer;
  - support arrow keys, home/end, page up/down, backspace, delete, ctrl-s save, and ctrl-c copy when a selection exists;
  - state changes mark row/caret layout dirty without rebuilding unrelated widgets;
  - unsupported key payloads return false explicitly.

- [ ] **Step 6: Implement selection and mouse hooks**

  Requirements:

  - clicking inside a row maps x/y to the row’s `column-byte-offsets` and moves the caret;
  - shift-navigation extends selection;
  - selected text copy calls `buffer:get-selected-text` and does not request whole file contents;
  - selection state is cleared on normal text insertion unless insertion replaces the selected range in the same operation.

- [ ] **Step 7: Validate Task 3**

  Run the same commands from Step 3, now including `--file assets/lua/virtual-input.fnl`. Expected: all pass.

- [ ] **Step 8: Run compatibility checks for existing input**

  Run:

  ```bash
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input-model:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
  ```

  Expected: both pass.

- [ ] **Step 9: Commit Task 3**

  ```bash
  git add assets/lua/virtual-input.fnl assets/lua/tests/test-virtual-input.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(ui): add virtual input widget"
  ```

---

### Task 4: Integrate VirtualInput into filesystem file viewer

**Files:**
- Modify: `assets/lua/graph/nodes/fs-file-viewer.fnl`
- Modify: `assets/lua/graph/view/views/fs-file-viewer.fnl`
- Modify: `assets/lua/tests/test-fs-file-viewer.fnl`

**Interfaces:**
- Consumes: `LazyTextSource.file`, `LazyTextBuffer`, `VirtualInput`, and `ExternalEditor.open-file`.
- Produces: `fs-file-viewer:<absolute-path>` graph nodes with editable lazy internal file input and explicit save/external-editor controls.

- [ ] **Step 1: Add failing integration tests**

  Extend `assets/lua/tests/test-fs-file-viewer.fnl` with tests named:

  ```fennel
  "fs-file-viewer builds VirtualInput for file contents"
  "fs-file-viewer saves internal edits to disk"
  "fs-file-viewer reports external modification conflict"
  "fs-file-viewer external editor affordance remains available"
  ```

  Required assertions:

  - returned view exposes `virtual-input`, `save-button`, `edit-button`, and `status-text`;
  - editing through `virtual-input:insert-text` changes buffer dirty state;
  - clicking Save writes the file through the lazy buffer save path;
  - modifying the file externally before Save reports conflict and does not overwrite;
  - external edit button and double-click affordance call `ExternalEditor.open-file` with the absolute path.

- [ ] **Step 2: Verify tests fail before implementation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-fs-file-viewer.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs-file-viewer:main
  ```

  Expected: focused test fails because the viewer still exposes bounded-window chunk controls.

- [ ] **Step 3: Update `FsFileViewerNode`**

  Requirements:

  - keep key format `fs-file-viewer:<absolute-path>`;
  - initialize `source` with `LazyTextSource.file(path)`;
  - initialize `buffer` with `LazyTextBuffer {:source source}`;
  - keep `open-external(callback)` unchanged;
  - keep graph persistence key-only by not serializing source, buffer, or edit state.

- [ ] **Step 4: Update `fs-file-viewer` view**

  Requirements:

  - build `VirtualInput {:buffer node.buffer :line-count 24 :column-count 100}`;
  - replace `Previous`, `Next`, and `Refresh` chunk controls with `Save` and `Edit externally` controls;
  - show status text for clean, dirty, saved, conflict, and error states;
  - double-click affordance still opens external editor unless it conflicts with text selection tests; if it conflicts, keep the explicit external editor button and document the double-click limitation in the task report.

- [ ] **Step 5: Validate Task 4**

  Run the same commands from Step 2, now including `--file assets/lua/graph/nodes/fs-file-viewer.fnl --file assets/lua/graph/view/views/fs-file-viewer.fnl --file assets/lua/virtual-input.fnl --file assets/lua/lazy-text-buffer.fnl --file assets/lua/lazy-text-source.fnl`. Expected: all pass.

- [ ] **Step 6: Commit Task 4**

  ```bash
  git add assets/lua/graph/nodes/fs-file-viewer.fnl assets/lua/graph/view/views/fs-file-viewer.fnl assets/lua/tests/test-fs-file-viewer.fnl
  git commit -m "feat(graph): edit files with virtual input"
  ```

---

### Task 5: Documentation and final validation

**Files:**
- Create: `docs/dev/features/lazy-text-buffer-virtual-input.md`
- Modify: `docs/dev/features/graph-filesystem-file-interactions.md`
- Modify: `docs/dev/features/index.md` if it exists and lists comparable feature pages.

**Interfaces:**
- Consumes: implemented native primitives, lazy source/buffer, `VirtualInput`, and filesystem viewer integration.
- Produces: developer documentation and final local validation evidence.

- [ ] **Step 1: Document the lazy editor stack**

  Create `docs/dev/features/lazy-text-buffer-virtual-input.md` with sections:

  ```markdown
  # Lazy Text Buffer and Virtual Input

  ## Use cases
  ## File source and save primitives
  ## Piece table buffer
  ## Sparse line index
  ## Viewport snapshots
  ## VirtualInput widget
  ## Save and conflict behavior
  ## Compatibility with Input/InputModel
  ## Testing expectations
  ```

  The doc must explicitly state: `Input` remains for small in-memory controls, `VirtualInput` is required for file-scale text, and file saves never blindly overwrite externally changed files.

- [ ] **Step 2: Update graph filesystem file interaction docs**

  Update `docs/dev/features/graph-filesystem-file-interactions.md` so `fs-file-viewer:<absolute-path>` is documented as an editable lazy `VirtualInput` node, not a read-only bounded chunk viewer.

- [ ] **Step 3: Add index link when applicable**

  If `docs/dev/features/index.md` lists similar feature pages, add `lazy-text-buffer-virtual-input` using the existing link style. If the file does not exist or is not a link index, record that in the report and do not create unrelated index structure.

- [ ] **Step 4: Run docs-focused checks**

  Run:

  ```bash
  rg "Lazy Text Buffer|VirtualInput|atomic-replace-if-current|file changed" docs/dev/features/lazy-text-buffer-virtual-input.md docs/dev/features/graph-filesystem-file-interactions.md
  rg "read-only bounded chunks|Previous|Next" docs/dev/features/graph-filesystem-file-interactions.md
  ```

  Expected: first command finds the new docs; second command returns no stale read-only chunk wording.

- [ ] **Step 5: Run full validation ladder**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-lazy-text-buffer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-virtual-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs-file-viewer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input-model:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-input:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: all pass. If any command fails, invoke systematic debugging before proposing fixes, establish root cause or evidence limits, route repository fixes through implementer and reviewer, and rerun validation.

- [ ] **Step 6: Commit Task 5**

  ```bash
  git add docs/dev/features/lazy-text-buffer-virtual-input.md docs/dev/features/graph-filesystem-file-interactions.md docs/dev/features/index.md
  git commit -m "docs(ui): document lazy virtual input"
  ```

## Final Review Checklist

- [ ] `fs-file-viewer` uses `VirtualInput` and no longer uses chunk-only text display for the internal path.
- [ ] `VirtualInput` does not pass whole files or whole composed documents to `Text`.
- [ ] Lazy buffer tests prove bounded source reads and piece-table editing.
- [ ] Save tests prove conflict detection prevents external overwrites.
- [ ] Existing `Input` and `InputModel` tests still pass.
- [ ] Graph persistence remains key-only and does not serialize edit buffers.
- [ ] PR CI remains the full integration gate before claiming ready-to-merge.
