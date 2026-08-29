# Graph Filesystem File Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make regular filesystem graph file nodes expose explicit file interactions, including external edit, type-specific module nodes, and a bounded lazy text viewer.

**Architecture:** Keep `fs:<path>` as the generic filesystem path adapter. Directory paths keep the existing directory-entry SearchView, while regular file paths render a SearchView of explicit file interaction rows. Add a dedicated `fs-file-viewer:<absolute-path>` UX-purpose node/view backed by a bounded C++ `fs.read-text-window` API so large files are never loaded wholesale.

**Tech Stack:** C++17 filesystem bindings in `src/lua_fs.cpp`; Space Fennel graph nodes, views, and key loaders under `assets/lua/graph`; existing `SearchView`, `Button`, `Text`, and `Flex` widgets; Fennel tests under `assets/lua/tests`; dev docs under `docs/dev`.

## Global Constraints

- `fs:<path>` remains the filesystem path adapter.
- Directory behavior remains unchanged: opening a directory entry materializes a child `fs:<child-path>` node and adds an explicit edge.
- Regular files build file-interaction search rows instead of directory-entry rows.
- File interaction rows are explicit data objects with a `kind` field; labels are display text only.
- The internal viewer is read-only in this iteration.
- The internal viewer must read bounded windows only and must not use `fs.read-file` or `Input` for file contents.
- Double-clicking internal viewer content opens the external editor through `ExternalEditor.open-file`.
- Graph persistence stores only visible node keys and edge keys; file content remains owned by the filesystem.
- File type detection is conservative and extension-based for this iteration.
- Unknown regular files expose only the safe external-editor interaction.
- Use `local` instead of `let` in new Fennel code.
- Widget builders must assert required context instead of silently falling back.
- For Fennel/UI changes, run project-native Fennel validation: compile check, constraints, focused tests.
- Because this changes C++ bindings, graph key loading, graph node behavior, and graph UI behavior, final validation must include `make build` and the broader test suite.

---

## File Structure

- `src/lua_fs.cpp`: add the bounded text-window filesystem binding.
- `assets/lua/graph/file-types.fnl`: centralize graph-facing extension classification.
- `assets/lua/graph/nodes/fs-file-viewer.fnl`: new UX-purpose graph node for lazy read-only file viewing.
- `assets/lua/graph/view/views/fs-file-viewer.fnl`: bounded file viewer UI.
- `assets/lua/graph/nodes/fs.fnl`: branch `FsNode` directory vs file behavior and dispatch file interaction rows.
- `assets/lua/graph/view/views/fs.fnl`: render file-mode as SearchView-only while preserving directory-mode controls.
- `assets/lua/graph/key-loaders.fnl`: register `fs-file-viewer:` loader.
- `assets/lua/tests/test-fs.fnl`: add bounded read tests.
- `assets/lua/tests/test-graph-file-types.fnl`: test file classification.
- `assets/lua/tests/test-fs-file-viewer.fnl`: test viewer node/view and key loader.
- `assets/lua/tests/test-graph-view.fnl`: test file-mode `FsNode` interactions and directory regression.
- `assets/lua/tests/fast.fnl`: register new focused tests.
- `docs/dev/features/graph-filesystem-file-interactions.md`: document behavior and invariants.
- `docs/dev/notes/graph.md`: cross-reference the file interaction doctrine.

---

### Task 1: Add bounded filesystem text-window reads

**Files:**
- Modify: `src/lua_fs.cpp`
- Modify: `assets/lua/tests/test-fs.fnl`

**Interfaces:**
- Consumes: existing `fs.write-file`, `fs.stat`, and `fs.read-file` test style.
- Produces: `fs.read-text-window(path: string, offset: number, max-bytes: number) -> table` with fields `path`, `offset`, `next-offset`, `size`, `bytes-read`, `eof`, `text`, and `truncated-utf8`.

- [ ] **Step 1: Add failing tests to `assets/lua/tests/test-fs.fnl`**

  Add tests named:

  ```fennel
  "fs read-text-window reads bounded range"
  "fs read-text-window caps max bytes"
  "fs read-text-window sanitizes display text"
  "fs read-text-window rejects invalid arguments"
  ```

  The bounded-range test must create `window.txt` containing `abcdef`, call `(fs.read-text-window file 2 3)`, and assert:

  ```fennel
  (= window.path file)
  (= window.offset 2)
  (= window.next-offset 5)
  (= window.size 6)
  (= window.bytes-read 3)
  (not window.eof)
  (= window.text "cde")
  (= window.truncated-utf8 false)
  ```

  The cap test must call `(fs.read-text-window file 0 999999)` on a file larger than `262144` bytes and assert `bytes-read`, `# text`, and `next-offset` are exactly `262144`.

  The sanitization test must write bytes containing an embedded NUL and byte `255`, then assert the returned `text` contains no NUL and contains replacement character `U+FFFD`.

  The invalid-argument test must assert that empty path, negative offset, and zero `max-bytes` each fail with error text containing `fs.read_text_window`.

- [ ] **Step 2: Verify the tests fail before implementation**

  Run:

  ```bash
  make build
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-fs.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs:main
  ```

  Expected: compile and constraints pass; focused test fails because `fs.read-text-window` is missing.

- [ ] **Step 3: Implement `fs_read_text_window` in `src/lua_fs.cpp`**

  Add bounded read behavior with these exact requirements:

  ```cpp
  constexpr std::uint64_t kMaxTextWindowBytes = 262144;
  sol::table fs_read_text_window(sol::this_state ts,
                                 const std::string& path,
                                 std::int64_t offset,
                                 std::int64_t max_bytes);
  ```

  The function must:

  - throw `sol::error("fs.read_text_window: path must be non-empty")` for an empty path;
  - throw `sol::error("fs.read_text_window: offset must be non-negative")` for negative offset;
  - throw `sol::error("fs.read_text_window: max-bytes must be positive")` for `max_bytes <= 0`;
  - cap reads at `kMaxTextWindowBytes`;
  - use `std::filesystem::file_size` for `size`;
  - use `std::ifstream(path, std::ios::binary)`, `seekg`, and bounded `read`;
  - never use `std::ostringstream buffer << file.rdbuf()` in this function;
  - replace embedded NULs and invalid UTF-8 with UTF-8 replacement character bytes `EF BF BD`;
  - set `truncated-utf8` when the final raw bytes end inside a multibyte sequence;
  - return the table fields listed in this task’s interface.

- [ ] **Step 4: Register the binding**

  In `create_fs_table`, add:

  ```cpp
  fs_table.set_function("read-text-window", &fs_read_text_window);
  ```

- [ ] **Step 5: Validate Task 1**

  Run the same commands from Step 2. Expected: all pass.

- [ ] **Step 6: Commit Task 1**

  ```bash
  git add src/lua_fs.cpp assets/lua/tests/test-fs.fnl
  git commit -m "feat(engine): add bounded filesystem text windows"
  ```

---

### Task 2: Add graph file type classification

**Files:**
- Create: `assets/lua/graph/file-types.fnl`
- Create: `assets/lua/tests/test-graph-file-types.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: path strings.
- Produces: `FileTypes.classify(path: string) -> table` with fields `path`, `basename`, `extension`, `text?`, `viewer?`, `module-kind`, `module-label`, and `module-key-prefix`.

- [ ] **Step 1: Add failing tests**

  Create `assets/lua/tests/test-graph-file-types.fnl` with tests named:

  ```fennel
  "graph file types classifies Fennel"
  "graph file types classifies C++ family"
  "graph file types classifies generic text"
  "graph file types omits binary unknown"
  "graph file types rejects invalid paths"
  ```

  Required assertions:

  ```fennel
  (local info (FileTypes.classify "/tmp/main.fnl"))
  (assert info.text?)
  (assert info.viewer?)
  (assert (= info.extension ".fnl"))
  (assert (= info.module-kind :fnl))
  (assert (= info.module-label "Open as Fennel Module"))
  (assert (= info.module-key-prefix "fnl-module:"))
  ```

  Repeat equivalent assertions for C++ paths `main.cpp`, `main.cc`, `main.cxx`, `main.h`, `main.hpp`, and `main.hh`, expecting `:cpp`, `Open as C++ Module`, and `cpp-module:`.

  Repeat equivalent assertions for generic text paths `README.md`, `note.txt`, `config.json`, `settings.toml`, `app.lua`, `script.py`, `CMakeLists.txt`, `Makefile`, and `Dockerfile`, expecting `:text`, `Open as Text Module`, and `text-module:`.

  For `blob.bin`, `image.png`, `archive.zip`, and `no-extension`, assert `text?` and `viewer?` are false and module fields are nil.

  For empty path, assert `pcall` fails with `graph.file-types classify requires a non-empty path`.

- [ ] **Step 2: Register the test**

  Add `:tests.test-graph-file-types` to `assets/lua/tests/fast.fnl` near existing graph test modules.

- [ ] **Step 3: Verify the tests fail before implementation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-file-types.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-file-types:main
  ```

  Expected: compile or focused test fails because `graph/file-types.fnl` does not exist.

- [ ] **Step 4: Implement `assets/lua/graph/file-types.fnl`**

  Implement `classify` with these exact rules:

  - reject non-string or empty paths with error text `graph.file-types classify requires a non-empty path`;
  - derive lowercase basename and extension;
  - classify `.fnl` as `:fnl`, label `Open as Fennel Module`, prefix `fnl-module:`;
  - classify `.cpp`, `.cc`, `.cxx`, `.h`, `.hpp`, `.hh` as `:cpp`, label `Open as C++ Module`, prefix `cpp-module:`;
  - classify `.lua`, `.md`, `.markdown`, `.txt`, `.text`, `.json`, `.jsonl`, `.toml`, `.yaml`, `.yml`, `.ini`, `.cfg`, `.conf`, `.csv`, `.tsv`, `.log`, `.sh`, `.bash`, `.zsh`, `.fish`, `.py`, `.js`, `.ts`, `.tsx`, `.jsx`, `.html`, `.css`, `.scss`, `.xml`, `.sql`, `.rs`, `.go`, `.java`, `.kt`, `.swift`, `.rb`, `.php`, `.cmake`, and `.nix` as `:text`, label `Open as Text Module`, prefix `text-module:`;
  - classify basenames `makefile`, `dockerfile`, and `cmakelists.txt` as generic text;
  - return `text? false`, `viewer? false`, and nil module fields for unknown files.

- [ ] **Step 5: Validate Task 2**

  Run the same commands from Step 3, but include `--file assets/lua/graph/file-types.fnl` in the compile check. Expected: all pass.

- [ ] **Step 6: Commit Task 2**

  ```bash
  git add assets/lua/graph/file-types.fnl assets/lua/tests/test-graph-file-types.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): classify filesystem file types"
  ```

---

### Task 3: Add lazy filesystem file viewer node and view

**Files:**
- Create: `assets/lua/graph/nodes/fs-file-viewer.fnl`
- Create: `assets/lua/graph/view/views/fs-file-viewer.fnl`
- Create: `assets/lua/tests/test-fs-file-viewer.fnl`
- Modify: `assets/lua/graph/key-loaders.fnl`
- Modify: `assets/lua/tests/fast.fnl`

**Interfaces:**
- Consumes: `fs.read-text-window(path, offset, max-bytes)` and `ExternalEditor.open-file(path, callback)`.
- Produces: `FsFileViewerNode(opts: table) -> node`, key format `fs-file-viewer:<absolute-path>`, and node methods `load-window`, `next-window`, `previous-window`, `refresh-window`, and `open-external`.

- [ ] **Step 1: Add failing viewer tests**

  Create `assets/lua/tests/test-fs-file-viewer.fnl` with tests named:

  ```fennel
  "fs-file-viewer node reads bounded windows"
  "fs-file-viewer key loader loads existing file"
  "fs-file-viewer view controls refresh and open external"
  ```

  The node test must create a file containing `abcdefghi`, construct `(FsFileViewerNode {:path file :window-size 3})`, then assert:

  ```fennel
  (= (: (node:load-window 0) :text) "abc")
  (= node.offset 0)
  (= (: (node:next-window) :text) "def")
  (= node.offset 3)
  (= (: (node:next-window) :text) "ghi")
  (= node.offset 6)
  (= (: (node:previous-window) :text) "def")
  (= node.offset 3)
  ```

  The key-loader test must register graph key loaders and assert `(graph:load-by-key (.. "fs-file-viewer:" abs))` returns a node with matching key and path.

  The view test must stub `ExternalEditor.open-file`, build the node view in a test context, assert initial text is `abc`, click `next-button`, `previous-button`, `refresh-button`, `content-button:on-double-click`, and `edit-button:on-click`, and assert the external editor receives the absolute file path.

- [ ] **Step 2: Register the test**

  Add `:tests.test-fs-file-viewer` to `assets/lua/tests/fast.fnl` near graph/filesystem tests.

- [ ] **Step 3: Verify the tests fail before implementation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-fs-file-viewer.fnl --file assets/lua/tests/fast.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs-file-viewer:main
  ```

  Expected: compile or focused test fails because the viewer node/view do not exist.

- [ ] **Step 4: Implement `assets/lua/graph/nodes/fs-file-viewer.fnl`**

  Required behavior:

  ```fennel
  (local default-window-size 65536)
  (fn FsFileViewerNode [opts] ...)
  ```

  - require `glm`, `graph/node-base`, `graph/view/views/fs-file-viewer`, `signal`, `external-editor`, and `fs`;
  - normalize `path` with `fs.absolute`;
  - assert `fs.stat(path).exists` and `fs.stat(path).is-file` with error text containing `FsFileViewerNode requires an existing file path`;
  - construct a `GraphNode` with key `fs-file-viewer:<absolute-path>`, label `View <absolute-path>`, and view `FsFileViewerNodeView`;
  - store `path`, `offset`, `window-size`, `window`, `previous-offsets`, and `window-changed`;
  - do not read file contents in the constructor;
  - `load-window(offset)` calls only `fs.read-text-window`, stores the returned table, updates `self.offset`, emits `window-changed`, and returns the window;
  - `next-window()` loads offset `0` if no window exists; otherwise pushes the current offset to history and loads `window.next-offset` when not at EOF;
  - `previous-window()` pops an offset from history, or returns the current window when history is empty;
  - `refresh-window()` reloads `self.offset`;
  - `open-external(callback)` calls `ExternalEditor.open-file self.path (or callback (fn [] nil))` and returns `true`;
  - `drop()` clears `window-changed`.

- [ ] **Step 5: Implement `assets/lua/graph/view/views/fs-file-viewer.fnl`**

  Required behavior:

  - require `flex`, `button`, and `text`;
  - assert build context exists;
  - build text-only buttons `Previous`, `Next`, `Refresh`, and `Edit externally`;
  - build content as a double-clickable `Button` containing a `Text` widget;
  - wire content double-click and edit button to `node:open-external()`;
  - call `node:refresh-window()` once during build;
  - connect to `node.window-changed` and update content and metadata text;
  - metadata text must include `Offset <offset>`, `Bytes <bytes-read>`, and `Size <size>`;
  - return view fields `previous-button`, `next-button`, `refresh-button`, `edit-button`, `content-button`, `content-text`, `metadata-text`, `layout`, and `drop`;
  - `drop()` disconnects the signal handler and drops the root layout.

- [ ] **Step 6: Register the key loader**

  In `assets/lua/graph/key-loaders.fnl`, require the node and add:

  ```fennel
  (graph:register-key-loader "fs-file-viewer"
    (existing-path-loader "fs-file-viewer:" :file
      (fn [path key]
        (FsFileViewerNode {:path path :key key}))))
  ```

- [ ] **Step 7: Validate Task 3**

  Run the same commands from Step 3, but include `--file assets/lua/graph/nodes/fs-file-viewer.fnl --file assets/lua/graph/view/views/fs-file-viewer.fnl --file assets/lua/graph/key-loaders.fnl` in the compile check. Expected: all pass.

- [ ] **Step 8: Commit Task 3**

  ```bash
  git add assets/lua/graph/nodes/fs-file-viewer.fnl assets/lua/graph/view/views/fs-file-viewer.fnl assets/lua/graph/key-loaders.fnl assets/lua/tests/test-fs-file-viewer.fnl assets/lua/tests/fast.fnl
  git commit -m "feat(graph): add lazy filesystem file viewer"
  ```

---

### Task 4: Convert regular file `FsNode` views to interaction SearchViews

**Files:**
- Modify: `assets/lua/graph/nodes/fs.fnl`
- Modify: `assets/lua/graph/view/views/fs.fnl`
- Modify: `assets/lua/tests/test-graph-view.fnl`

**Interfaces:**
- Consumes: `FileTypes.classify`, `FsFileViewerNode`, existing module node constructors, and existing directory `FsNode` behavior.
- Produces: file-mode `FsNode` SearchView rows with `kind` values `:external-editor`, `:file-viewer`, and `:module`; `FsNode:open-file-interaction(interaction) -> node | true`.

- [ ] **Step 1: Add failing graph tests**

  In `assets/lua/tests/test-graph-view.fnl`, add helper functions:

  ```fennel
  (fn find-search-row [items label]
    (var found nil)
    (each [_ item (ipairs items)]
      (when (= (. item 2) label)
        (set found (. item 1))))
    found)

  (fn search-labels [items]
    (icollect [_ item (ipairs items)]
      (. item 2)))
  ```

  Add tests named:

  ```fennel
  "FsNode file view renders only search interactions"
  "FsNode external editor interaction does not add edge"
  "FsNode text viewer interaction adds viewer node"
  "FsNode module interactions preserve key formats"
  "FsNode unknown file shows only external editor"
  "FsNode directory listing behavior remains unchanged"
  ```

  Required assertions:

  - a `.fnl` file node view has `view.action-row nil`;
  - its `view.search.items` contains labels `Edit externally`, `View text`, and `Open as Fennel Module`;
  - row objects have `kind :external-editor`, `kind :file-viewer`, and `kind :module`;
  - replacing `node.list-directory` with a function that errors does not break file-mode rendering;
  - opening `Edit externally` calls `ExternalEditor.open-file` and leaves `graph:edge-count` at `0`;
  - opening `View text` adds key `fs-file-viewer:<absolute-path>` and one edge;
  - opening `.fnl`, `.cpp`, and `.md` module rows adds `fnl-module:`, `cpp-module:`, and `text-module:` keys respectively;
  - unknown `blob.bin` exposes exactly one label, `Edit externally`;
  - a directory node still lists a child directory as `child/` and a child file as `note.txt` with no interaction `kind`.

- [ ] **Step 2: Verify the tests fail before implementation**

  Run:

  ```bash
  SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tools.fennel-check:main -- --target files --file assets/lua/tests/test-graph-view.fnl
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  ```

  Expected: compile and constraints pass; focused graph-view test fails because file-mode `FsNode` still renders the directory-oriented view.

- [ ] **Step 3: Refactor `assets/lua/graph/nodes/fs.fnl`**

  Required behavior:

  - require `graph/file-types` and `graph/nodes/fs-file-viewer`;
  - remove duplicated local Fennel/C++ extension helpers;
  - add `node.path-stat(path)` returning `(values resolved-path stat)`;
  - move existing directory list logic into `node.build-directory-items(current-path)` unchanged;
  - add `node.build-file-interactions(current-path)` that always adds `Edit externally`, adds `View text` when `classification.viewer?`, and adds one module row when `classification.module-kind` is non-nil;
  - change `node.build-items(current-path)` to branch on `stat.is-dir` vs `stat.is-file` and error with `FsNode path is not a directory or regular file` otherwise;
  - add `node.open-file-interaction(interaction)`:

  ```fennel
  :external-editor -> ExternalEditor.open-file interaction.path (fn [] nil), return true
  :file-viewer -> add GraphEdge to FsFileViewerNode {:path interaction.path :key interaction.target-key}
  :module -> add GraphEdge to self:create-module-node interaction.module-kind interaction.path
  unknown -> error containing "FsNode unsupported file interaction kind"
  ```

  - change `node.open-entry(entry)` to dispatch to `open-file-interaction` when `entry.kind` exists and keep directory-entry behavior otherwise.

- [ ] **Step 4: Update `node.actions` in `assets/lua/graph/nodes/fs.fnl`**

  Keep existing compatibility actions, but use `FileTypes.classify(resolved-path)` for module action decisions. Do not add a viewer action to `node.actions`; the viewer is exposed through SearchView rows.

- [ ] **Step 5: Update `assets/lua/graph/view/views/fs.fnl`**

  Required behavior:

  - determine `file-mode?` with `fs.stat(resolved-path).is-file`;
  - file mode builds only the `SearchView` and sets `view.action-row`, `view.edit-button`, and `view.ripgrep-button` to nil;
  - directory mode keeps the current action row with Edit/Ripgrep behavior;
  - keep `set-items`, `refresh-items`, `search.submitted`, signal connection, and `drop` behavior intact.

- [ ] **Step 6: Validate Task 4**

  Run the same commands from Step 2, but include `--file assets/lua/graph/nodes/fs.fnl --file assets/lua/graph/view/views/fs.fnl` in the compile check. Expected: all pass.

- [ ] **Step 7: Commit Task 4**

  ```bash
  git add assets/lua/graph/nodes/fs.fnl assets/lua/graph/view/views/fs.fnl assets/lua/tests/test-graph-view.fnl
  git commit -m "feat(graph): show filesystem file interactions"
  ```

---

### Task 5: Document filesystem file interactions and run final validation

**Files:**
- Create: `docs/dev/features/graph-filesystem-file-interactions.md`
- Modify: `docs/dev/notes/graph.md`

**Interfaces:**
- Consumes: implemented behavior from Tasks 1-4.
- Produces: developer-facing documentation and final validation evidence.

- [ ] **Step 1: Create `docs/dev/features/graph-filesystem-file-interactions.md`**

  Include these sections and facts:

  ```markdown
  # Graph Filesystem File Interactions

  `fs:<path>` is the generic filesystem path adapter. Directory paths render the existing searchable directory listing and opening an entry materializes a child `fs:<child-path>` node with an explicit edge.

  Regular file paths render a SearchView of explicit interaction rows. Interaction rows are data objects with `kind` fields; labels are display text only.

  ## File interactions

  - `:external-editor` opens `ExternalEditor.open-file(path, callback)` and does not add graph topology.
  - `:file-viewer` materializes `fs-file-viewer:<absolute-path>` and adds an explicit edge from the file `FsNode`.
  - `:module` materializes `fnl-module:<absolute-path>`, `cpp-module:<absolute-path>`, or `text-module:<absolute-path>` and adds an explicit edge.

  ## Bounded internal viewer

  `fs-file-viewer:<absolute-path>` is a UX-purpose graph node. It owns viewer state such as current byte offset, previous offsets, and current bounded window metadata. It does not own or persist file content.

  The viewer reads through `fs.read-text-window(path, offset, max-bytes)`, which caps reads at 262144 bytes, seeks to the requested zero-based byte offset, sanitizes display text, and returns bounded window metadata. Viewer UI must not use `Input` or `fs.read-file`.

  Double-clicking the viewer content opens the external editor. Internal editing and saving are not part of this feature.

  ## Persistence invariant

  Graph persistence stores visible node keys and explicit edge keys only. File content remains owned by the filesystem and is never captured in graph topology state.
  ```

- [ ] **Step 2: Cross-reference from `docs/dev/notes/graph.md`**

  Add this bullet under “Preview vs UX node vs full view”:

  ```markdown
  - Filesystem file content follows the same exposure-layer rule: `fs:<path>` remains the generic path adapter, regular files expose explicit interaction rows, and `fs-file-viewer:<absolute-path>` is a UX-purpose node that reads only bounded windows. See [Graph Filesystem File Interactions](/dev/features/graph-filesystem-file-interactions).
  ```

- [ ] **Step 3: Run docs-focused checks**

  Run:

  ```bash
  rg "fs-file-viewer|read-text-window|Graph Filesystem File Interactions" docs/dev/features/graph-filesystem-file-interactions.md docs/dev/notes/graph.md
  rg "fs.read-file|Input" assets/lua/graph/nodes/fs-file-viewer.fnl assets/lua/graph/view/views/fs-file-viewer.fnl
  ```

  Expected: first command finds the new documentation references; second command returns no matches.

- [ ] **Step 4: Run full validation**

  Run:

  ```bash
  make build
  make fennel-check
  make constraints
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-file-types:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-fs-file-viewer:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets FENNEL_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" FENNEL_MACRO_PATH="$(pwd)/assets/lua/?.fnl;$(pwd)/assets/lua/?/init.fnl" ./build/space -m tests.test-graph-view:main
  SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 SPACE_ASSETS_PATH=$(pwd)/assets make test
  ```

  Expected: all pass. If any command fails, invoke `systematic-debugging`, identify root cause or evidence limits, route any repository fix through implementer and reviewer, and rerun the failed command plus downstream validation from a clean tree.

- [ ] **Step 5: Commit Task 5**

  ```bash
  git add docs/dev/features/graph-filesystem-file-interactions.md docs/dev/notes/graph.md
  git commit -m "docs(graph): document filesystem file interactions"
  ```

## Final Self-Review and Acceptance Notes

- [ ] Confirm `fs:<path>` remains the generic adapter for both directories and files.
- [ ] Confirm directory `FsNode` listing/open-entry behavior is unchanged.
- [ ] Confirm regular file `FsNode` rendering uses explicit SearchView interaction rows and does not call `fs.list-dir`.
- [ ] Confirm viewer code does not use `fs.read-file` or `Input`.
- [ ] Confirm graph persistence contains only node keys and edge keys, never file content.
- [ ] Confirm out-of-scope items remain unimplemented: internal editing/saving, full-file loading, MIME database integration, file watching/live reload, full virtualized file scrolling, and `FsNode` key-family split.
- [ ] Confirm final integration status is gated by PR CI.
