;; Test-Isolation constraint rules for experimental Fennel constraints.
;; One rule: global-mutation-restoration

(local Diagnostics (require :constraints.diagnostics))
(local M {})

(local sensitive ["app.renderers" "app.lights" "app.engine" "app.activity-registry" "app.physics-containment-config" "package.loaded"])

(fn path-prefix-matches? [mp sg-parts plen]
  "Check if the mutation path head matches the sensitive-global path prefix."
  (local slen (length sg-parts))
  (if (< plen slen) false
      (do
        (var matches true)
        (for [i 1 slen]
          (when (not (= (. mp i) (. sg-parts i)))
            (set matches false)))
        matches)))

(fn mutation-path-is-sensitive? [mutation-path]
  (local mp (if mutation-path mutation-path []))
  (local plen (length mp))
  (if (< plen 2) false
      (do
        (var found false)
        (each [_ sg (ipairs sensitive)]
          (when (not found)
            (local sg-parts [])
            (each [seg (sg:gmatch "[^%.]+")] (table.insert sg-parts seg))
            (when (path-prefix-matches? mp sg-parts plen)
              (set found true))))
        found)))

(fn escape-pattern [s]
  "Escape Lua pattern magic characters in a string."
  (s:gsub "[%]%[%%%.%*%+%-%?%(%)%^%$]" "%%%1"))

(fn def-contains-line? [def line]
  "Check if a function definition contains the given source line.
   Computes end-line from the form text's newline count."
  (var form-lines 0)
  (each [_ _ (def.form:gmatch "\n")]
    (set form-lines (+ form-lines 1)))
  (local end-line (+ def.line form-lines))
  (and (>= line def.line) (<= line end-line)))

(fn find-containing-fn-defs [definitions line col]
  "Find all fn definitions that contain the given line.
   col is optional; when two definitions share the same start line,
   the one with the later column (closer to col) is sorted first.
   Returns a list sorted by start-line descending (innermost first)."
  (var result [])
  (var defs definitions)
  (when (not defs) (set defs []))
  (each [_ def (ipairs defs)]
    (when (and (= def.kind :fn) (def-contains-line? def line))
      (table.insert result def)))
  (var sorted false)
  (while (not sorted)
    (set sorted true)
    (for [i 1 (- (length result) 1)]
      (local a (. result i))
      (local b (. result (+ i 1)))
      (when (if (< a.line b.line) true
                (and (= a.line b.line) col
                     (< a.column b.column)
                     (<= b.column col)) true
                false)
        (tset result i b)
        (tset result (+ i 1) a)
        (set sorted false))))
  result)

(fn find-matching-close [text open-pos]
  "Find the matching close paren/bracket for the opener at open-pos.
   Returns the byte position of the matching close, or nil."
  (local open-ch (text:sub open-pos open-pos))
  (local close-ch (if (= open-ch "(") ")"
                       (= open-ch "[") "]"
                       (= open-ch "{") "}"))
  (if (not close-ch) nil
      (do
        (var depth 1)
        (var pos (+ open-pos 1))
        (var result nil)
        (while (and (> depth 0) (<= pos (length text)))
          (local ch (text:sub pos pos))
          (if (= ch open-ch) (set depth (+ depth 1))
              (= ch close-ch) (do (set depth (- depth 1))
                                  (when (= depth 0) (set result pos)))
              (= ch "\"") (do (local eq (text:find "\"" (+ pos 1) true))
                              (when eq (set pos eq))))
          (set pos (+ pos 1)))
        result)))

(fn find-helper-snapshot-var [fn-form path-text]
  "Find all snapshot variables whose snapshot keys cover the given path.
   Returns a list of variable names, or empty list if none found.
   Pairs variable identity with coverage so that the restore variable
   must be one whose snapshot covers the mutated path."
  (var result [])
  (var had-any-literal false)
  (var had-any-resolved false)
  (var first-unresolved-var nil)
  ;; Check literal vector snapshots: (local VAR (snapshot-app-fields [:k1 :k2 ...]))
  (local lit-pat "%(local%s+([%w%-_]+)%s+%(snapshot%-app%-fields%s+%[(.-)%]%s*%)%)")
  (each [var-name keys-str (fn-form:gmatch lit-pat)]
    (set had-any-literal true)
    (var covers false)
    (each [k (keys-str:gmatch ":?([%w%-%.]+)")]
      (when (and (not covers) (> (length k) 0))
        (local app-key (.. "app." k))
        (local ekey (escape-pattern app-key))
        (when (if (= path-text app-key) true
                  (path-text:find (.. "^" ekey "%.") 1 false) true
                  false)
          (set covers true))))
    (when covers (table.insert result var-name)))
  ;; Check variable-key snapshots: (local VAR (snapshot-app-fields KEY-VAR))
  (when (= (length result) 0)
    (local var-pat "%(local%s+([%w%-_]+)%s+%(snapshot%-app%-fields%s+([%w%-_]+)%s*%)%)")
    (each [snap-var key-var (fn-form:gmatch var-pat)]
      (local ekv (escape-pattern key-var))
      (local local-pat (.. "%(local%s+" ekv "%s+%[(.-)%]"))
      (var this-resolved false)
      (var this-covers false)
      (each [keys-str (fn-form:gmatch local-pat)]
        (set this-resolved true)
        (set had-any-resolved true)
        (when (not this-covers)
          (each [k (keys-str:gmatch ":?([%w%-%.]+)")]
            (when (and (not this-covers) (> (length k) 0))
              (local app-key (.. "app." k))
              (local ekey (escape-pattern app-key))
              (when (if (= path-text app-key) true
                        (path-text:find (.. "^" ekey "%.") 1 false) true
                        false)
                (set this-covers true))))))
      (when this-covers (table.insert result snap-var))
      (when (and (not this-resolved) (not first-unresolved-var))
        (set first-unresolved-var snap-var))))
  ;; Fallback: no literal, no resolved variable, but found unresolved var key -> accept
  (when (and (= (length result) 0) (not had-any-literal) (not had-any-resolved) first-unresolved-var)
    (table.insert result first-unresolved-var))
  result)

(fn find-substring [s pat init]
  "Like string.find but returns {:start start :end end} or nil.
   Captures all return values into a table to avoid double-calling string.find."
  (local result [(string.find s pat init)])
  (if (. result 1)
      {:start (. result 1) :end (. result 2)}
      nil))

(fn position-to-file-line [fn-form fn-def-line byte-pos]
  "Convert a byte position in the form text to an approximate file line."
  (var line fn-def-line)
  (local prefix (fn-form:sub 1 byte-pos))
  (each [_ (prefix:gmatch "\n")]
    (set line (+ line 1)))
  line)

(fn has-helper-restore-after-line? [fn-form fn-def-line path-text min-line]
  "Check for snapshot-app-fields + restore-app-fields! with restore after min-line.
   Any snapshot variable covering the path, when restored after the mutation, is accepted."
  (local all-vars (find-helper-snapshot-var fn-form path-text))
  (var found false)
  (var vi 1)
  (while (and (not found) (<= vi (length all-vars)))
    (local snap-var (. all-vars vi))
    (local pat (.. "restore%-app%-fields!%s+" (escape-pattern snap-var)))
    (var search-start 1)
    (while (and (not found) search-start)
      (local s-e (find-substring fn-form pat search-start))
      (if s-e
          (do
            (local start s-e.start)
            (local end s-e.end)
            (local restore-line (position-to-file-line fn-form fn-def-line start))
            (if (>= restore-line min-line)
                (set found true)
                (set search-start (+ end 1))))
          (set search-start nil)))
    (set vi (+ vi 1)))
  found)

(fn has-helper-restore-after-byte? [fn-form path-text min-byte]
  "Check for snapshot-app-fields + restore-app-fields! with restore after min-byte.
   Any snapshot variable covering the path, when restored after the mutation, is accepted."
  (local all-vars (find-helper-snapshot-var fn-form path-text))
  (var found false)
  (var vi 1)
  (while (and (not found) (<= vi (length all-vars)))
    (local snap-var (. all-vars vi))
    (local pat (.. "restore%-app%-fields!%s+" (escape-pattern snap-var)))
    (var search-start 1)
    (while (and (not found) search-start)
      (local s-e (find-substring fn-form pat search-start))
      (if s-e
          (do
            (local start s-e.start)
            (local end s-e.end)
            (if (>= start min-byte)
                (set found true)
                (set search-start (+ end 1))))
          (set search-start nil)))
    (set vi (+ vi 1)))
  found)

(fn skip-argument [text start]
  "Skip past one S-expression argument (vector, list, or symbol) at start.
   Returns byte position after the argument, or nil if text ends first."
  (var pos start)
  ;; Skip leading whitespace
  (while (<= pos (length text))
    (local ch (text:sub pos pos))
    (if (if (= ch " ") true (= ch "\n") true (= ch "\t") true false)
        (set pos (+ pos 1))
        (lua :break)))
  (if (> pos (length text)) nil
      (do
        (local ch (text:sub pos pos))
        (if (if (= ch "[") true (= ch "(") true false)
            (do (local close (find-matching-close text pos))
                (if close (+ close 1) nil))
            ;; Symbol: scan to next delimiter or paren
            (do
              (var sp pos)
              (while (<= sp (length text))
                (local c (text:sub sp sp))
                (if (if (= c " ") true (= c "\n") true (= c "\t") true (= c ")") true false)
                    (lua :break)
                    (set sp (+ sp 1))))
              sp)))))

(fn anon-byte-inside-wraf-body? [parent-form anon-byte]
  "Check if the byte position in parent-form falls inside a
   with-restored-app-fields body (past the keys argument).
   Handles both vector literal and variable key arguments."
  (var inside false)
  (var search-pos 1)
  (local token "with-restored-app-fields")
  (local token-len (length token))
  (while (and (not inside) search-pos)
    (local token-start (string.find parent-form token search-pos true))
    (if (and token-start (< token-start anon-byte))
        (do
          (var op nil)
          (for [i (- token-start 1) 1 -1]
            (when (and (not op) (= (parent-form:sub i i) "("))
              (set op i)))
          (if op
              (do
                (local call-end (find-matching-close parent-form op))
                (if (and call-end (< anon-byte call-end))
                    (do
                      (local body-start (skip-argument parent-form (+ token-start token-len)))
                      (if (and body-start (>= anon-byte body-start))
                          (set inside true)
                          (set search-pos (+ token-start token-len))))
                    (set search-pos (+ call-end 1))))
              (set search-pos (+ token-start token-len))))
        (set search-pos nil)))
  inside)

(fn is-test-infrastructure-fn? [file-path fn-name]
  "Narrow exemption for test environment construction functions that are
   not per-test mutation risks."
  (if (and (string.find file-path "/tests/runner.fnl" 1 true)
           (= fn-name "setup-test-env")) true
      (and (string.find file-path "/tests/e2e/harness.fnl" 1 true)
           (= fn-name "init-test-app")) true
      false))

(fn find-snapshot-var [fn-form path]
  "Find the first snapshot variable bound to the given path via let or local.
   Returns the variable name as a string, or nil if none found."
  (local path-text (table.concat path "."))
  (local escaped-path (path-text:gsub "%." "%%."))
  (var snap-var nil)
  ;; Check (let [VAR path ...] ...) patterns
  (each [v (fn-form:gmatch (.. "%(let%s*%[%s*([^%s]+)%s+" escaped-path))]
    (when (not snap-var)
      (set snap-var v)))
  ;; Check (local VAR path ...) patterns
  (when (not snap-var)
    (each [v (fn-form:gmatch (.. "%(local%s+([^%s]+)%s+" escaped-path))]
      (when (not snap-var)
        (set snap-var v))))
  snap-var)

(fn has-concrete-restore-after-line? [fn-form fn-def-line path min-line]
  "Check for concrete restore evidence at or after min-line in the source.
   The function form must show both a snapshot of the path into a local
   variable and a later write that sets the path back to that variable
   at a source line >= min-line."
  (local snap-var (find-snapshot-var fn-form path))
  (if (not snap-var) false
      (do
        (local path-text (table.concat path "."))
        (local escaped-path (path-text:gsub "%." "%%."))
        (local escaped-var (escape-pattern snap-var))
        (var found false)
         ;; Scan (set path_text snap-var) positions
         (local set-pat (.. "%(set%s+" escaped-path "%s+" escaped-var "%s*%)"))
         (var search-start 1)
         (while (and (not found) search-start)
           (local s-e (find-substring fn-form set-pat search-start))
           (if s-e
               (do
                 (local start s-e.start)
                 (local end s-e.end)
                 (local restore-line (position-to-file-line fn-form fn-def-line start))
                 (if (>= restore-line min-line)
                     (set found true)
                     (set search-start (+ end 1))))
               (set search-start nil)))
        ;; Scan tset positions
        (when (and (not found) (>= (length path) 2))
          (local plen (length path))
          (local table-parts [])
          (for [i 1 (- plen 1)]
            (table.insert table-parts (. path i)))
          (local tset-table (table.concat table-parts "."))
          (local key (. path plen))
          (local escaped-tset (tset-table:gsub "%." "%%."))
          (local escaped-key (escape-pattern key))
          (local pat1 (.. "%(tset%s+" escaped-tset "%s+:%s*" escaped-key "%s+" escaped-var))
          (local pat2 (.. "%(tset%s+" escaped-tset "%s+\"%s*" escaped-key "%s*\"%s+" escaped-var))
          (set search-start 1)
          (while (and (not found) search-start)
             (local s-e1 (find-substring fn-form pat1 search-start))
             (if s-e1
                 (do
                   (local start1 s-e1.start)
                   (local end1 s-e1.end)
                   (local restore-line (position-to-file-line fn-form fn-def-line start1))
                   (if (>= restore-line min-line)
                       (set found true)
                       (set search-start (+ end1 1))))
                 (do
                   (local s-e2 (find-substring fn-form pat2 search-start))
                   (if s-e2
                       (do
                         (local start2 s-e2.start)
                         (local end2 s-e2.end)
                         (local restore-line (position-to-file-line fn-form fn-def-line start2))
                         (if (>= restore-line min-line)
                             (set found true)
                             (set search-start (+ end2 1))))
                       (set search-start nil))))))
        found)))

(fn try-extract-pcall-range [fn-form pcall-start]
  "Try to find the fn body end for a pcall+fn form starting at pcall-start.
   Returns {:fn-start fn-start :fn-end end-pos} or nil if no inner fn found."
  (local fn-start (string.find fn-form "%(fn[%s%)]" pcall-start false))
  (if (not fn-start) nil
      (do
        (var depth 1)
        (var pos (+ fn-start 4))
        (var end-pos nil)
        (while (and (> depth 0) (<= pos (length fn-form)))
          (local ch (fn-form:sub pos pos))
          (if (= ch "(") (set depth (+ depth 1))
              (= ch ")") (do (set depth (- depth 1))
                             (when (= depth 0)
                               (set end-pos pos)))
              (= ch "\"") (do
                            (local end-quote (fn-form:find "\"" (+ pos 1) true))
                            (when end-quote (set pos end-quote))))
          (set pos (+ pos 1)))
        (if end-pos {:fn-start fn-start :fn-end end-pos} nil))))

(fn find-all-pcall-fn-ranges [fn-form]
  "Find all (pcall (fn [...] ...)) forms and return their fn body byte ranges.
   Returns a list of {:fn-start :fn-end} where fn-start is the byte position
   of the '(' before 'fn' and fn-end is the matching close paren of the fn form.
   Skips pcall calls that don't have a (fn [...] body (e.g. (pcall some-fn))."
  (var ranges [])
  (var search-pos 1)
  (while search-pos
    (local pcall-start (string.find fn-form "pcall" search-pos true))
    (if pcall-start
        (do
          (local pcall-result (try-extract-pcall-range fn-form pcall-start))
          (if pcall-result
              (do
                (table.insert ranges pcall-result)
                (set search-pos (+ pcall-result.fn-end 1)))
              (set search-pos (+ pcall-start 5))))
        (set search-pos nil)))
  ranges)

(fn find-mutation-approx-byte [fn-form fn-def-line target-line]
  "Convert a file line number to an approximate byte position in the form text.
   The form text starts at fn-def-line in the file, so position 1 corresponds
   to fn-def-line. Each newline in the form text advances the file line by 1.
   Returns the byte position after the newline that reaches target-line,
   or 1 if target-line equals fn-def-line."
  (if (<= target-line fn-def-line) 1
      (do
        (var byte-pos 1)
        (var current-line fn-def-line)
        (var search-pos 1)
        (while (and (< current-line target-line) search-pos (<= search-pos (length fn-form)))
          (local nl-pos (string.find fn-form "\n" search-pos true))
          (if nl-pos
              (do
                (set current-line (+ current-line 1))
                (set search-pos (+ nl-pos 1))
                (set byte-pos (+ nl-pos 1)))
              (set search-pos nil)))
        byte-pos)))

(fn find-enclosing-pcall-end-byte [fn-form fn-def-line max-mutation-line pcall-ranges]
  "Find the end byte of the pcall fn body that encloses the mutation position.
   Uses the max mutation line to approximate the mutation byte position in the
   form text, then checks which pcall body range (if any) contains it.
   Returns the :fn-end byte of the enclosing pcall body, or nil if the mutation
   is not inside any pcall body."
  (local mutation-byte (find-mutation-approx-byte fn-form fn-def-line max-mutation-line))
  (var enclosing-end nil)
  (each [_ range (ipairs pcall-ranges)]
    (when (and (<= range.fn-start mutation-byte) (>= range.fn-end mutation-byte))
      (set enclosing-end range.fn-end)))
  enclosing-end)

(fn has-concrete-restore-after-byte? [fn-form fn-def-line path min-byte]
  "Check for concrete restore evidence at a byte position >= min-byte.
   Like has-concrete-restore-after-line? but compares start byte position
   instead of approximate line number. Used for pcall where the restore
   must be textually after the pcall body's closing paren."
  (local snap-var (find-snapshot-var fn-form path))
  (if (not snap-var) false
      (do
        (local path-text (table.concat path "."))
        (local escaped-path (path-text:gsub "%." "%%."))
        (local escaped-var (escape-pattern snap-var))
        (var found false)
         ;; Scan (set path_text snap-var) positions
         (local set-pat (.. "%(set%s+" escaped-path "%s+" escaped-var "%s*%)"))
         (var search-start 1)
         (while (and (not found) search-start)
           (local s-e (find-substring fn-form set-pat search-start))
           (if s-e
               (do
                 (local start s-e.start)
                 (local end s-e.end)
                 (if (>= start min-byte)
                     (set found true)
                     (set search-start (+ end 1))))
               (set search-start nil)))
         ;; Scan tset positions  
         (when (and (not found) (>= (length path) 2))
           (local plen (length path))
           (local table-parts [])
           (for [i 1 (- plen 1)]
             (table.insert table-parts (. path i)))
           (local tset-table (table.concat table-parts "."))
           (local key (. path plen))
           (local escaped-tset (tset-table:gsub "%." "%%."))
           (local escaped-key (escape-pattern key))
           (local pat1 (.. "%(tset%s+" escaped-tset "%s+:%s*" escaped-key "%s+" escaped-var))
           (local pat2 (.. "%(tset%s+" escaped-tset "%s+\"%s*" escaped-key "%s*\"%s+" escaped-var))
           (set search-start 1)
           (while (and (not found) search-start)
             (local s-e1 (find-substring fn-form pat1 search-start))
             (if s-e1
                 (do
                   (local start1 s-e1.start)
                   (local end1 s-e1.end)
                   (if (>= start1 min-byte)
                       (set found true)
                       (set search-start (+ end1 1))))
                 (do
                   (local s-e2 (find-substring fn-form pat2 search-start))
                   (if s-e2
                       (do
                         (local start2 s-e2.start)
                         (local end2 s-e2.end)
                         (if (>= start2 min-byte)
                             (set found true)
                             (set search-start (+ end2 1))))
                       (set search-start nil))))))
        found)))

;; --- Extracted helpers for global-mutation-restoration-rule-run ---

(fn build-mutation-group-key [mutation ff]
  "Build the grouping key for a single mutation: fn-key::path-text.
   For anonymous functions, includes @LINE:COLUMN for disambiguation."
  (local fn-name (if mutation.enclosing-fn mutation.enclosing-fn "<top-level>"))
  (local path-text (table.concat (if mutation.path mutation.path []) "."))
  (local fn-key
    (if (= fn-name "<anonymous>")
        (do
          (local containing (find-containing-fn-defs ff.definitions mutation.line mutation.column))
          (if (> (length containing) 0)
              (do
                (local def (. containing 1))
                (.. fn-name "@" def.line ":" def.column))
              fn-name))
        fn-name))
  (.. fn-key "::" path-text))

(fn parse-group-key [key]
  "Parse a grouping key into fn-name, anon-def-line, anon-def-col, path-text.
   Returns nil if key has no :: separator."
  (local sep (key:find "::" 1 true))
  (if (not sep) nil
      (do
        (local raw-fn-key (key:sub 1 (- sep 1)))
        (local path-text (key:sub (+ sep 2)))
        (local is-anon (raw-fn-key:find "<anonymous>@" 1 true))
        (local fn-name (if is-anon "<anonymous>" raw-fn-key))
        (local anon-def-line
          (if is-anon
              (do
                (local rest (raw-fn-key:sub 11))
                (tonumber (rest:match "^([0-9]+)")))
              nil))
        (local anon-def-col
          (if is-anon
              (do
                (local rest (raw-fn-key:sub 11))
                (local col-str (rest:match ":(%d+)$"))
                (if col-str (tonumber col-str) 1))
              nil))
        {:fn-name fn-name
         :anon-def-line anon-def-line
         :anon-def-col anon-def-col
         :path-text path-text
         :is-anon is-anon})))

(fn resolve-fn-form [ff fn-name anon-def-line anon-def-col max-line]
  "Find the function form and its definition line for a given function name.
   Returns {:fn-form ... :fn-def-line ...} or {:fn-form nil :fn-def-line nil}."
  (if (= fn-name "<top-level>")
      {:fn-form nil :fn-def-line nil}
      (if (= fn-name "<anonymous>")
          (do
            (local search-line (if anon-def-line anon-def-line max-line))
            (local search-col (if anon-def-col anon-def-col nil))
            (local containing (find-containing-fn-defs ff.definitions search-line search-col))
            (if (> (length containing) 0)
                (do
                  (local def (. containing 1))
                  {:fn-form def.form :fn-def-line def.line})
                {:fn-form nil :fn-def-line nil}))
          ;; Named functions: match by name
          (do
            (var defs ff.definitions)
            (when (not defs) (set defs []))
            (var ffm nil)
            (var ffd nil)
            (each [_ def (ipairs defs)]
              (when (and (= def.kind :fn) (= def.name fn-name))
                (set ffm def.form)
                (set ffd def.line)))
            {:fn-form ffm :fn-def-line ffd}))))

(fn check-parent-wrapper [ff fn-def-line anon-def-col]
  "Check Pattern 3: parent function wrapper for anonymous functions.
   Returns true if the anonymous fn is inside a with-restored-app-fields body
   in the parent function."
  (local search-col (if anon-def-col anon-def-col nil))
  (local containing (find-containing-fn-defs ff.definitions fn-def-line search-col))
  (if (<= (length containing) 1) false
      (do
        (local parent (. containing 2))
        (local anon-def (. containing 1))
        (local anon-line-byte (find-mutation-approx-byte parent.form parent.line fn-def-line))
        (local col (if anon-def.column anon-def.column 1))
        (local anon-byte (+ anon-line-byte (math.max 0 (- col 1))))
        (if (anon-byte-inside-wraf-body? parent.form anon-byte) true false))))

(fn emit-mutation-diagnostic [diagnostics diagnosed key ff path-text max-line fn-name]
  "Record a violation diagnostic for an unrestored sensitive global mutation."
  (tset diagnosed key true)
  (table.insert diagnostics
    (Diagnostics.violation
      {:constraint-id "lifecycle.global-mutation-restoration"
       :family "test-isolation"
       :message (.. "test file mutates sensitive global " path-text " without snapshot and restore")
       :file ff.path :line max-line :column 0
       :evidence {:global-path path-text :enclosing-fn fn-name}
       :hint (.. "snapshot and restore " path-text " using with-restored-app-fields or pcall cleanup")})))

(fn global-mutation-restoration-rule-run [ctx]
  (var diagnostics [])
  (var files (. ctx.facts :files))
  (when (not files) (set files []))
  (each [_ ff (ipairs files)]
    (when (string.find ff.path "/tests/" 1 true)
      ;; Step 1: collect max mutation line per (concrete fn, path) group
      (var fn-path-max-line {})
      (var mutations ff.mutations)
      (when (not mutations) (set mutations []))
      (each [_ mutation (ipairs mutations)]
        (when (mutation-path-is-sensitive? mutation.path)
          (local key (build-mutation-group-key mutation ff))
          (local current-max (if (. fn-path-max-line key) (. fn-path-max-line key) 0))
          (when (> mutation.line current-max)
            (tset fn-path-max-line key mutation.line))))
      ;; Step 2: for each (fn, path) group, check restoration after max line
      (var diagnosed {})
      (each [key max-line (pairs fn-path-max-line)]
        (when (not (. diagnosed key))
          (local parsed (parse-group-key key))
          (when parsed
            (local fn-name parsed.fn-name)
            (local anon-def-line parsed.anon-def-line)
            (local anon-def-col parsed.anon-def-col)
            (local path-text parsed.path-text)
            (local result (resolve-fn-form ff fn-name anon-def-line anon-def-col max-line))
            (local fn-form result.fn-form)
            (local fn-def-line result.fn-def-line)
            ;; Check restoration patterns (order-aware)
            (var has-restoration false)
            (when (and fn-form fn-def-line)
              ;; Narrow exemption: test infra setup functions
              (when (is-test-infrastructure-fn? ff.path fn-name)
                (set has-restoration true))
              ;; Build path-segments from path-text
              (local path-segments [])
              (each [seg (path-text:gmatch "[^%.]+")]
                (table.insert path-segments seg))
              ;; Pattern 1: with-restored-app-fields (explicit)
              (when (and (not has-restoration)
                         (string.find fn-form "with-restored-app-fields" 1 true))
                (set has-restoration true))
              ;; Pattern 3: parent function wrapper for anonymous functions.
              (when (and (not has-restoration) (= fn-name "<anonymous>"))
                (when (check-parent-wrapper ff fn-def-line anon-def-col)
                  (set has-restoration true)))
              ;; Determine whether the mutation is inside a pcall body.
              (local pcall-ranges (find-all-pcall-fn-ranges fn-form))
              (local enclosing-pcall-end (find-enclosing-pcall-end-byte fn-form fn-def-line max-line pcall-ranges))
              ;; Pattern 4a: direct snapshot table restore (order-aware, non-pcall)
              (when (and (not has-restoration) (not enclosing-pcall-end))
                (when (has-concrete-restore-after-line? fn-form fn-def-line path-segments max-line)
                  (set has-restoration true)))
              ;; Pattern 4b: helper snapshot/restore pair (order-aware, non-pcall)
              (when (and (not has-restoration) (not enclosing-pcall-end))
                (when (has-helper-restore-after-line? fn-form fn-def-line path-text max-line)
                  (set has-restoration true)))
              ;; Pattern 5a: pcall concrete restore (order-aware)
              (when (and (not has-restoration) enclosing-pcall-end)
                (when (has-concrete-restore-after-byte? fn-form fn-def-line path-segments enclosing-pcall-end)
                  (set has-restoration true)))
              ;; Pattern 5b: pcall helper restore (order-aware)
              (when (and (not has-restoration) enclosing-pcall-end)
                (when (has-helper-restore-after-byte? fn-form path-text enclosing-pcall-end)
                  (set has-restoration true)))
            ;; Emit diagnostic if no valid restoration found
            (when (not has-restoration)
              (emit-mutation-diagnostic diagnostics diagnosed key ff path-text max-line fn-name))))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.global-mutation-restoration" :family "test-isolation" :targets [:repo] :kind :static :run global-mutation-restoration-rule-run :fn global-mutation-restoration-rule-run}])

M
