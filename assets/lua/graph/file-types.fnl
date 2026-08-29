(local M {})

(local classification-by-extension
  {".fnl" {:module-kind :fnl
           :module-label "Open as Fennel Module"
           :module-key-prefix "fnl-module:"}
   ".cpp" {:module-kind :cpp
           :module-label "Open as C++ Module"
           :module-key-prefix "cpp-module:"}
   ".cc" {:module-kind :cpp
          :module-label "Open as C++ Module"
          :module-key-prefix "cpp-module:"}
   ".cxx" {:module-kind :cpp
           :module-label "Open as C++ Module"
           :module-key-prefix "cpp-module:"}
   ".h" {:module-kind :cpp
         :module-label "Open as C++ Module"
         :module-key-prefix "cpp-module:"}
   ".hpp" {:module-kind :cpp
           :module-label "Open as C++ Module"
           :module-key-prefix "cpp-module:"}
   ".hh" {:module-kind :cpp
          :module-label "Open as C++ Module"
          :module-key-prefix "cpp-module:"}})

(local generic-text-extensions
  {".lua" true
   ".md" true
   ".markdown" true
   ".txt" true
   ".text" true
   ".json" true
   ".jsonl" true
   ".toml" true
   ".yaml" true
   ".yml" true
   ".ini" true
   ".cfg" true
   ".conf" true
   ".csv" true
   ".tsv" true
   ".log" true
   ".sh" true
   ".bash" true
   ".zsh" true
   ".fish" true
   ".py" true
   ".js" true
   ".ts" true
   ".tsx" true
   ".jsx" true
   ".html" true
   ".css" true
   ".scss" true
   ".xml" true
   ".sql" true
   ".rs" true
   ".go" true
   ".java" true
   ".kt" true
   ".swift" true
   ".rb" true
   ".php" true
   ".cmake" true
   ".nix" true})

(local generic-text-basenames
  {:makefile true
   :dockerfile true
   :cmakelists.txt true})

(local generic-text-classification
  {:module-kind :text
   :module-label "Open as Text Module"
   :module-key-prefix "text-module:"})

(fn basename-for [path]
  (local matched (string.match path "[^/]+$"))
  (if matched
      matched
      path))

(fn extension-for [basename]
  (local matched (string.match basename "(%.[^%.]+)$"))
  (if matched
      matched
      ""))

(fn result [path basename extension classification]
  (if classification
      {:path path
       :basename basename
       :extension extension
       :text? true
       :viewer? true
       :module-kind classification.module-kind
       :module-label classification.module-label
       :module-key-prefix classification.module-key-prefix}
      {:path path
       :basename basename
       :extension extension
       :text? false
       :viewer? false}))

(fn M.classify [path]
  (when (or (not (= (type path) :string))
            (= path ""))
    (error "graph.file-types classify requires a non-empty path"))
  (local basename (string.lower (basename-for path)))
  (local extension (extension-for basename))
  (local classification
    (if (. classification-by-extension extension)
        (. classification-by-extension extension)
        (or (and (. generic-text-extensions extension) generic-text-classification)
            (and (. generic-text-basenames basename) generic-text-classification))))
  (result path basename extension classification))

M
