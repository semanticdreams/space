# Lazy Text Buffer and Virtual Input

## Use cases

The lazy editor stack supports file-scale text viewing and editing without loading the whole file into a Fennel string, an `InputModel`, or a single `Text` widget. Use it for graph filesystem file viewer nodes and other features that must open large source, log, or plain-text files while keeping reads and rendered widgets bounded to the active viewport.

This stack is intentionally plain text only in this iteration. It does not provide syntax highlighting, undo/redo history, modal editing, multi-cursor behavior, whole-file search/replace, binary editing, or collaborative editing.

## File source and save primitives

`LazyTextSource.file(path, opts)` normalizes the path, captures a filesystem token with `fs.file-token`, and exposes bounded reads through `fs.read-byte-range`. The source keeps the baseline token that represents the file version the buffer was opened from and can refresh that baseline after a successful save.

Native filesystem saves use `fs.atomic-replace-if-current(path, segments, expected-token)`. Segment tables may reference unchanged byte ranges from the original source file or provide inserted text. The native primitive validates that the current file still matches `expected-token`, writes the composed content to a temporary replacement, revalidates the token after the temporary file is complete, and atomically installs it only if the token is still current.

## Piece table buffer

`LazyTextBuffer {:source source}` represents the document as a piece table. Original pieces reference byte ranges in the file source, while inserted text is appended to an add buffer. Insert and delete operations rewrite piece metadata and leave unchanged file content on disk instead of copying the complete file into memory.

The buffer tracks byte-position caret state, optional selection ranges, dirty state, and the current scroll line. Editing methods fail loudly for unsupported or invalid input, including invalid UTF-8 inserted text.

## Sparse line index

Line navigation is backed by sparse byte anchors. The buffer starts with a line-zero anchor and discovers additional line starts only as viewport, caret, or navigation requests require them. This keeps indexing work proportional to the explored region rather than requiring an eager scan of the entire file.

When edits change document structure, line anchors reset to the beginning so later navigation rebuilds the sparse index against the current piece table.

## Viewport snapshots

`buffer:get-viewport {:line line :column column :lines lines :columns columns}` returns a bounded snapshot containing only requested rows and visible columns. Rows include text/codepoints for display plus byte offsets needed for caret movement and selection.

Viewport construction reads composed ranges in bounded chunks and marks long rows as partial when the row exceeds the scan budget. The editor must not fall back to whole-file reads when lazy indexing or row discovery is incomplete.

## VirtualInput widget

`VirtualInput` is the file-scale text widget. It renders a fixed number of visible rows by feeding each visible row's codepoints to child `Text` widgets, routes keyboard editing to `LazyTextBuffer`, tracks viewport scroll, handles selection/copy, and exposes save handling for buffers that support saving.

`VirtualInput` builders require an explicit build context and a lazy buffer. It must be used for file-scale text because it virtualizes both data access and child rendering; no new large-file path should pass a whole file or whole composed document to `Text` or `Input`.

## Save and conflict behavior

Saves never blindly overwrite externally changed files. Before the graph file viewer saves, it compares the current file token with the buffer source baseline token and reports a conflict if the file changed externally. The buffer save itself delegates to `atomic-replace-if-current`, which repeats the token check at the native filesystem boundary after composing the replacement and immediately before replacing the file.

On successful save, the buffer refreshes its baseline token, collapses pieces back to a single original-file piece, clears the add buffer, and marks itself clean. On conflict or error, the buffer remains dirty so the caller can report the problem and preserve the user's in-memory edits.

## Compatibility with Input/InputModel

`Input` and `InputModel` remain the correct widgets for small in-memory controls such as labels, prompts, forms, and compact text fields. They keep their existing whole-buffer codepoint behavior and compatibility tests.

`VirtualInput` is required for file-scale text. Existing whole-buffer input controls must not be repurposed for large files, and the lazy stack exists beside them rather than replacing their small-control responsibilities.

## Testing expectations

Validation for this stack should cover the full ladder because it spans native filesystem primitives, lazy Fennel buffers, UI input behavior, and graph file interactions:

- `make build` after native binding or runtime changes.
- `make fennel-check` before constraints and Fennel tests.
- `make constraints` as the structural gate.
- Focused tests for `tests.test-fs`, `tests.test-lazy-text-buffer`, `tests.test-virtual-input`, `tests.test-fs-file-viewer`, `tests.test-input-model`, and `tests.test-input`.
- The standard full `make test` command with keyring skipped, audio disabled, and `SPACE_ASSETS_PATH` set to the absolute assets directory.

Regression tests should prove bounded reads, piece-table editing, viewport-only rendering, save success, conflict detection with `file changed` errors, graph viewer integration, and continued `Input`/`InputModel` compatibility.
