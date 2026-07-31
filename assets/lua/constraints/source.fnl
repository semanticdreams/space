;; Source discovery and parsing for experimental Fennel constraints.
;; Provides file discovery, tree-sitter parsing, traversal, and text extraction.

(local ts (require :tree-sitter))
(local fs (require :fs))

(local M {})

(fn list-fnl-files [root]
  "Recursively collect .fnl file paths under root, sorted lexicographically.
  Excludes hidden directories (those starting with '.').
  Errors if root cannot be listed (unreadable, missing, etc.), with path context."
  (let [files []]
    (fn walk [dir]
      (let [(ok entries) (pcall #(fs.list-dir dir false))]
        (if (not ok)
            (error (.. "failed to list directory " dir ": " (tostring entries)))
            (each [_ entry (ipairs entries)]
              (if entry.is-dir
                  (walk entry.path)
                  (and entry.is-file
                       (or (entry.name:match "%.fnl$")
                           (entry.path:match "%.fnl$")))
                  (table.insert files (fs.absolute entry.path)))))))
    (walk root)
    ;; Sort lexicographically for deterministic ordering
    (table.sort files)
    files))

(fn str-escape-pattern [s]
  "Escape Lua pattern magic characters in string s for use in string.match patterns."
  (s:gsub "([%.%-%+%*%?%[%]%(%)%%])" "%%%1"))

(fn compute-module [file-path module-roots]
  "Compute a module name from file-path by removing .fnl and replacing / with .,
  relative to the first matching module root.
  Returns the original path if no root matches."
  (var module-name file-path)
  (var found false)
  (each [_ root (ipairs module-roots)]
    (when (not found)
      ;; Check if file is under this root (case-insensitive)
      (let [root-lower (root:lower)
            file-lower (file-path:lower)]
        (when (or (= file-lower root-lower)
                  (file-lower:match (.. "^" (str-escape-pattern root-lower) "/")))
          (let [relative (if (= (# file-path) (# root))
                            file-path
                            (file-path:sub (+ (# root) 2)))]
            (let [no-ext (relative:gsub "%.fnl$" "")]
              (set module-name (no-ext:gsub "/" "."))
              (set found true)))))))
  module-name)

(fn compute-relative-path [file-path module-roots]
  "Compute the relative path of file-path under the first matching module root.
  Preserves the .fnl extension and subdirectory structure.
  Returns the original path if no module root matches."
  (var rel-path file-path)
  (var found false)
  (each [_ root (ipairs module-roots)]
    (when (not found)
      (let [root-lower (root:lower)
            file-lower (file-path:lower)]
        (when (or (= file-lower root-lower)
                  (file-lower:match (.. "^" (str-escape-pattern root-lower) "/")))
          (set rel-path (if (= (# file-path) (# root))
                           file-path
                           (file-path:sub (+ (# root) 2))))
          (set found true)))))
  rel-path)

(fn M.node-text [source node]
  "Extract the substring of source covered by node's byte range.
  Tree-sitter byte offsets are 0-indexed; Lua strings are 1-indexed."
  (source:sub (+ (node:start-byte) 1) (node:end-byte)))

(fn M.node-location [node]
  "Return {:line integer :column integer} for the start of node.
  Maps tree-sitter's row/column to Fennel/Lua line/column convention."
  (let [pt (node:start-point)]
    {:line (+ pt.row 1)
     :column (+ pt.column 1)}))

(fn M.walk [node f]
  "Call f on every node in a depth-first traversal."
  (f node)
  (for [i 0 (- (node:child-count) 1)]
    (M.walk (node:child i) f)))

(fn M.discover [target]
  "Discover and parse Fennel source files for a target.
  Returns a list of file-records:
  [{:target target
    :path absolute-path-string
    :module string
    :source string
    :tree TSTree
    :root TSNode} ...]"
  (var file-paths [])
  ;; Collect files from roots (may throw on unreadable root)
  (each [_ root (ipairs (or target.roots []))]
    (each [_ f (ipairs (list-fnl-files root))]
      (table.insert file-paths f)))
  ;; Collect explicit files — only .fnl paths
  (each [_ f (ipairs (or target.files []))]
    (let [abs (fs.absolute f)]
      (when (abs:match "%.fnl$")
        (table.insert file-paths abs))))
  ;; Deduplicate paths
  (table.sort file-paths)
  (var seen {})
  (local deduped [])
  (each [_ path (ipairs file-paths)]
    (when (not (. seen path))
      (tset seen path true)
      (table.insert deduped path)))
  ;; Parse each file
  (local module-roots (or target.module-roots target.roots []))
  (local records [])
  (each [_ path (ipairs deduped)]
    (let [source (fs.read-file path)
          tree (ts.parse source {:language :fennel})
          root (tree:root)
          module (compute-module path module-roots)
          relative-path (compute-relative-path path module-roots)]
      (table.insert records
        {:target target
         :path path
         :module module
         :relative-path relative-path
         :source source
         :tree tree
         :root root})))
  records)

M
