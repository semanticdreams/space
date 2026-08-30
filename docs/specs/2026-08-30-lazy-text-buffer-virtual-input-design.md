# Lazy Text Buffer and Virtual Input Design

## Context

The current `Input` widget provides the interaction shape users expect from text:
focus, caret movement, keyboard text entry, deletion, viewport handling, and
external-editor affordances. Its backing `InputModel`, however, is whole-buffer
oriented. It stores all text as a codepoint array, rebuilds derived line state
after edits, and derives cursor line/column by scanning that state. This is a
good fit for small in-memory fields, but not for filesystem-scale files.

The new graph filesystem `View text` flow proved the need for a better
foundation. It reads bounded file windows, so it avoids loading an entire file,
but it renders the bounded window through plain `Text` and lacks editor-like
interaction. A proper solution needs the interaction expectations of `Input`
without the whole-buffer storage assumptions.

## Goals

- Provide a `VirtualInput` widget for file-scale text viewing and editing.
- Keep existing `Input` and `InputModel` behavior compatible for small controls.
- Support arbitrarily large files by bounding source reads, visible rendering,
  and cached indexing work.
- Represent edits without loading unchanged file content into memory.
- Make the filesystem file viewer use `VirtualInput` for internal editing.
- Save safely: detect external file changes before writing and avoid blind
  overwrite.
- Test the buffer, widget, filesystem save path, and graph integration
  thoroughly.

## Non-goals

- No syntax highlighting in this iteration.
- No undo/redo history in this iteration.
- No multi-cursor editing.
- No Vim/Neovim modal command parity.
- No collaborative editing or CRDTs.
- No binary/hex editing.
- No search/replace over unloaded whole files.
- No retained backup-file policy beyond temporary files needed for atomic save.

## Design Direction

Build a new lazy text stack alongside the existing `Input` stack:

1. Native filesystem primitives expose file identity tokens, raw bounded byte
   reads, and safe conditional atomic replacement.
2. `LazyTextSource` adapts a file into bounded reads plus baseline metadata.
3. `LazyTextBuffer` uses a piece table to compose original file spans and edit
   spans without loading unchanged source bytes.
4. A sparse line index maps line numbers and byte offsets lazily, scanning only
   what the viewport or navigation requires.
5. `VirtualInput` renders only a viewport snapshot and handles caret,
   selection, text insertion/deletion, copy, scrolling, and save.
6. `fs-file-viewer:<path>` uses `VirtualInput` as its internal editor while
   preserving the external editor affordance.

This keeps the whole-buffer `Input` stable and gives file-scale text a purpose-
built model.

## Considered Approaches

### Approach A: Patch `InputModel` to swap lazy windows

This would reuse the existing `Input` widget directly, but the current model’s
state is globally indexed over a single codepoint array. Swapping windows would
make cursor positions, selections, copy behavior, edits across window
boundaries, and save semantics lie about the real document. It would also risk
breaking current small input users.

Decision: reject for this feature.

### Approach B: New `VirtualInput` over a Fennel piece table

Add a new widget and model stack. Keep source bytes in the file, edits in an
append-only add buffer, and the composed document as piece spans. Render only
visible rows. Save by streaming source spans and add spans through a guarded
filesystem write path.

Decision: recommended. It is testable in Fennel, minimally invasive to existing
widgets, and ready for editing semantics.

### Approach C: C++ editor core and renderer

Move buffer storage, indexing, save, and possibly rendering into C++. This has
the highest performance ceiling for very large and heavily edited files, but it
creates a large binding surface before the Space editor UX has stabilized.

Decision: defer until profiling proves the Fennel piece table is insufficient.

## Components

### Filesystem primitives

Add native APIs that are explicitly file-editor oriented:

- `fs.file-token(path)` returns file identity metadata: normalized path,
  existence, regular-file flag, size, modification timestamp, and permissions.
- `fs.read-byte-range(path, offset, max-bytes)` reads raw bytes from a byte
  offset and returns only that bounded range.
- `fs.atomic-replace-if-current(path, segments, expected-token, opts)` compares
  the current token with the expected token, writes a sibling temporary file from
  streamed segments, preserves permissions where possible, and atomically
  replaces the target only when the file has not changed externally.

The existing `fs.read-text-window` may remain for compatibility, but the editing
path should use raw byte ranges plus the lazy buffer.

### Lazy text source

`LazyTextSource.file(path, opts)` adapts a regular file. It owns the file path,
baseline token, file size, and read limits. It exposes bounded raw reads and can
refresh or compare file tokens. It does not decode the whole file.

### Lazy text buffer

`LazyTextBuffer` is the document model. It consumes a source and exposes editor
operations. Internally it uses:

- original pieces: spans of the source file;
- add pieces: spans of an append-only in-memory edit buffer;
- absolute composed-document byte offsets as canonical positions;
- cached line anchors mapping logical line numbers to byte offsets;
- viewport snapshots containing only requested visible rows.

The buffer is responsible for UTF-8 aware navigation and mapping between byte
offsets, codepoint columns, and rendered rows. Invalid original bytes are shown
with replacement characters but must be preserved if untouched.

Core methods should include:

- `get-viewport({line, column, lines, columns})`;
- `move-caret`, `move-caret-to-line-column`, `scroll-lines`, `scroll-columns`;
- `insert-text`, `delete-before-cursor`, `delete-at-cursor`;
- `set-selection`, `clear-selection`, `get-selected-text`;
- `save(opts)`.

### Sparse line index

The line index starts with an anchor at line 0, byte 0. It scans forward in
bounded chunks only as needed. It caches anchors for visited regions and
invalidates or rebases anchors affected by edits. It does not compute total line
count eagerly.

Line endings must support LF and CRLF. Viewport rows expose enough metadata for
caret and selection:

- logical line number;
- start and end byte offsets;
- display text/codepoints;
- newline byte length;
- mapping from codepoint column to byte offset.

### Virtual input widget

`VirtualInput` is a new widget, not a replacement for `Input`. It should borrow
the current input interaction model where practical: focus integration, caret
visuals, keyboard handling, mouse wheel scrolling, copy behavior, and context
menu patterns.

It renders only the current viewport. A practical first implementation can use a
bounded set of row `Text` widgets inside an explicit clipped layout. It must not
pass the whole file or whole composed document to `Text`.

The widget should provide explicit methods:

- `insert-text`;
- `delete-before-cursor`;
- `delete-at-cursor`;
- `move-caret` and directional navigation;
- `copy-selection`;
- `save`;
- `drop`.

### Filesystem viewer integration

`fs-file-viewer:<absolute-path>` remains the graph-visible UX-purpose node for
interacting with a filesystem text file. Its view should replace the current
bounded chunk display with `VirtualInput` backed by `LazyTextSource.file` and
`LazyTextBuffer`.

The viewer should expose:

- editable lazy text viewport;
- Save action;
- status metadata for dirty/saved/conflict/error states;
- external editor action;
- double-click affordance for external editor if it does not conflict with text
  interaction.

Graph persistence must still store only node keys and edges, never file content
or edit buffers.

## Save Semantics

Saving must be explicit and safe:

1. Capture a baseline file token when the source opens.
2. Track dirty state in `LazyTextBuffer` after edits.
3. On save, compare the current file token to the baseline token.
4. If the file changed externally, return or raise an explicit conflict and keep
   dirty state true.
5. If current, stream the piece table into a sibling temporary file.
6. Preserve target permissions where possible.
7. Atomically replace the target.
8. Refresh the baseline token and clear dirty state only after success.

No path may silently overwrite externally modified files.

## Error Handling

- Missing source path, non-regular files, invalid byte offsets, invalid segment
  specs, failed token comparison, and failed save operations must surface clear
  errors.
- `VirtualInput` builders must assert required context.
- Unsupported operations must fail loudly rather than no-op.
- The editor must not fall back to whole-file reads when lazy indexing is
  incomplete.

## Testing Strategy

Tests should be broader than the current file viewer tests because this becomes
a foundational editor abstraction.

### Filesystem primitive tests

- Raw range reads return bounded bytes and correct offsets.
- Invalid ranges fail loudly.
- File tokens change when size or modification time changes.
- Atomic replace succeeds when token matches.
- Atomic replace refuses when token differs.
- Segment validation rejects malformed source/text spans.

### Lazy buffer tests

- Opening a large generated file does not call `fs.read-file` and does not load
  the full file.
- Viewport snapshots read only bounded source chunks.
- LF and CRLF line indexing work across chunk boundaries.
- UTF-8 multibyte text maps byte offsets to codepoint columns correctly.
- Invalid original bytes display as replacement characters but remain preserved
  when untouched.
- Insert/delete works at beginning, middle, end, and across piece boundaries.
- Selection and copy work within and across pieces.
- Save streams original and add pieces correctly.
- Save conflict detection prevents external overwrite.

### Widget tests

- `VirtualInput` builds with explicit context and drops all owned children.
- It renders only configured visible rows.
- Caret movement across lazy-loaded lines updates viewport and caret metadata.
- Text insertion/deletion updates viewport, dirty state, and save status.
- Selection copy does not load the whole file.
- Save success and conflict statuses are surfaced.
- Existing `Input` and `InputModel` tests continue to pass.

### Graph integration tests

- `fs-file-viewer` opens a `VirtualInput` backed by the selected file.
- Internal edits save to disk through the safe path.
- External modification after open produces a conflict.
- External editor affordance still works.
- Graph persistence remains key-only.

## Acceptance Criteria

- A large text file can be opened through `fs-file-viewer` without whole-file
  reads or whole-document rendering.
- The visible editor behaves like a text input for navigation, selection, copy,
  insertion, deletion, and save.
- Edits are represented as pieces or equivalent overlays over the original file.
- Saving detects external changes and never blindly overwrites.
- Existing small `Input` users remain compatible.
- Tests cover source primitives, buffer behavior, widget behavior, graph
  integration, and compatibility with existing input tests.
