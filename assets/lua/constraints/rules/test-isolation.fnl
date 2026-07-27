;; Test-Isolation constraint rules for experimental Fennel constraints.
;; One rule: global-mutation-restoration

(local Diagnostics (require :constraints.diagnostics))
(local M {})

(local sensitive ["app.renderers" "app.lights" "app.engine" "app.activity-registry" "app.physics-containment-config" "package.loaded"])

(fn mutation-path-is-sensitive? [mutation-path]
  (let [plen (length (or mutation-path []))]
    (if (< plen 2) false
        (do
          (var found false)
          (each [_ sg (ipairs sensitive)]
            (when (not found)
              (local sg-parts [])
              (each [seg (sg:gmatch "[^%.]+")] (table.insert sg-parts seg))
              (let [slen (length sg-parts)]
                (when (>= plen slen)
                  (var matches true)
                  (for [i 1 slen]
                    (when (not (= (. mutation-path i) (. sg-parts i)))
                      (set matches false)))
                  (when matches (set found true))))))
          found))))

(fn escape-pattern [s]
  "Escape Lua pattern magic characters in a string."
  (s:gsub "[%]%[%%%.%*%+%-%?%(%)%^%$]" "%%%1"))

(fn position-to-file-line [fn-form fn-def-line byte-pos]
  "Convert a byte position in the form text to an approximate file line."
  (var line fn-def-line)
  (let [prefix (fn-form:sub 1 byte-pos)]
    (each [_ (prefix:gmatch "\n")]
      (set line (+ line 1))))
  line)

(fn find-snapshot-var [fn-form path]
  "Find the first snapshot variable bound to the given path via let or local.
   Returns the variable name as a string, or nil if none found."
  (let [path-text (table.concat path ".")
        escaped-path (path-text:gsub "%." "%%.")]
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
    snap-var))

(fn has-concrete-restore-after-line? [fn-form fn-def-line path min-line]
  "Check for concrete restore evidence at or after min-line in the source.
   The function form must show both a snapshot of the path into a local
   variable and a later write that sets the path back to that variable
   at a source line >= min-line."
  (let [snap-var (find-snapshot-var fn-form path)]
    (if (not snap-var)
        false
        (let [path-text (table.concat path ".")
              escaped-path (path-text:gsub "%." "%%.")
              escaped-var (escape-pattern snap-var)]
          (var found false)
          ;; Scan (set path_text snap-var) positions
          (let [set-pat (.. "%(set%s+" escaped-path "%s+" escaped-var "%s*%)")]
            (var search-start 1)
            (while (and (not found) search-start)
              (let [(start end) (string.find fn-form set-pat search-start)]
                (if start
                    (let [restore-line (position-to-file-line fn-form fn-def-line start)]
                      (if (>= restore-line min-line)
                          (set found true)
                          (set search-start (+ end 1))))
                    (lua :break)))))
          ;; Scan tset positions
          (when (and (not found) (>= (length path) 2))
            (let [plen (length path)]
              (local table-parts [])
              (for [i 1 (- plen 1)]
                (table.insert table-parts (. path i)))
              (let [tset-table (table.concat table-parts ".")
                    key (. path plen)
                    escaped-tset (tset-table:gsub "%." "%%.")
                    escaped-key (escape-pattern key)
                    pat1 (.. "%(tset%s+" escaped-tset "%s+:%s*" escaped-key "%s+" escaped-var)
                    pat2 (.. "%(tset%s+" escaped-tset "%s+\"%s*" escaped-key "%s*\"%s+" escaped-var)]
                (var search-start 1)
                (while (and (not found) search-start)
                  (let [(start1 end1) (string.find fn-form pat1 search-start)]
                    (if start1
                        (let [restore-line (position-to-file-line fn-form fn-def-line start1)]
                          (if (>= restore-line min-line)
                              (set found true)
                              (set search-start (+ end1 1))))
                        (let [(start2 end2) (string.find fn-form pat2 search-start)]
                          (if start2
                              (let [restore-line (position-to-file-line fn-form fn-def-line start2)]
                                (if (>= restore-line min-line)
                                    (set found true)
                                    (set search-start (+ end2 1))))
                              (lua :break)))))))))
          found))))

(fn find-all-pcall-fn-ranges [fn-form]
  "Find all (pcall (fn [...] ...)) forms and return their fn body byte ranges.
   Returns a list of {:fn-start :fn-end} where fn-start is the byte position
   of the '(' before 'fn' and fn-end is the matching close paren of the fn form.
   Skips pcall calls that don't have a (fn [...] body (e.g. (pcall some-fn))."
  (var ranges [])
  (var search-pos 1)
  (while search-pos
    (let [(pcall-start) (string.find fn-form "pcall" search-pos true)]
      (if pcall-start
          (let [(fn-start) (string.find fn-form "%(fn[%s%)]" pcall-start false)]
            (if fn-start
                ;; Got a pcall with an inner fn — find its closing paren
                (do
                  (var depth 1)
                  (var pos (+ fn-start 4))
                  (var end-pos nil)
                  (while (and (> depth 0) (<= pos (length fn-form)))
                    (let [ch (fn-form:sub pos pos)]
                      (if (= ch "(") (set depth (+ depth 1))
                          (= ch ")") (do (set depth (- depth 1))
                                         (when (= depth 0)
                                           (set end-pos pos)))
                          (= ch "\"") (let [end-quote (fn-form:find "\"" (+ pos 1) true)]
                                        (when end-quote (set pos end-quote)))))
                    (set pos (+ pos 1)))
                  (if end-pos
                      (do
                        (table.insert ranges {:fn-start fn-start :fn-end end-pos})
                        (set search-pos (+ end-pos 1)))
                      (set search-pos (+ pcall-start 5))))
                ;; pcall without (fn [...] — skip past this pcall
                (set search-pos (+ pcall-start 5))))
          (set search-pos nil))))
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
          (let [(nl-pos) (string.find fn-form "\n" search-pos true)]
            (if nl-pos
                (do
                  (set current-line (+ current-line 1))
                  (set search-pos (+ nl-pos 1))
                  (set byte-pos (+ nl-pos 1)))
                (set search-pos nil))))
        byte-pos)))

(fn find-enclosing-pcall-end-byte [fn-form fn-def-line max-mutation-line pcall-ranges]
  "Find the end byte of the pcall fn body that encloses the mutation position.
   Uses the max mutation line to approximate the mutation byte position in the
   form text, then checks which pcall body range (if any) contains it.
   Returns the :fn-end byte of the enclosing pcall body, or nil if the mutation
   is not inside any pcall body."
  (let [mutation-byte (find-mutation-approx-byte fn-form fn-def-line max-mutation-line)]
    (var enclosing-end nil)
    (each [_ range (ipairs pcall-ranges)]
      (when (and (<= range.fn-start mutation-byte) (>= range.fn-end mutation-byte))
        (set enclosing-end range.fn-end)))
    enclosing-end))

(fn has-concrete-restore-after-byte? [fn-form fn-def-line path min-byte]
  "Check for concrete restore evidence at a byte position >= min-byte.
   Like has-concrete-restore-after-line? but compares start byte position
   instead of approximate line number. Used for pcall where the restore
   must be textually after the pcall body's closing paren."
  (let [snap-var (find-snapshot-var fn-form path)]
    (if (not snap-var)
        false
        (let [path-text (table.concat path ".")
              escaped-path (path-text:gsub "%." "%%.")
              escaped-var (escape-pattern snap-var)]
          (var found false)
          ;; Scan (set path_text snap-var) positions
          (let [set-pat (.. "%(set%s+" escaped-path "%s+" escaped-var "%s*%)")]
            (var search-start 1)
            (while (and (not found) search-start)
              (let [(start end) (string.find fn-form set-pat search-start)]
                (if start
                    (if (>= start min-byte)
                        (set found true)
                        (set search-start (+ end 1)))
                    (lua :break)))))
          ;; Scan tset positions  
          (when (and (not found) (>= (length path) 2))
            (let [plen (length path)]
              (local table-parts [])
              (for [i 1 (- plen 1)]
                (table.insert table-parts (. path i)))
              (let [tset-table (table.concat table-parts ".")
                    key (. path plen)
                    escaped-tset (tset-table:gsub "%." "%%.")
                    escaped-key (escape-pattern key)
                    pat1 (.. "%(tset%s+" escaped-tset "%s+:%s*" escaped-key "%s+" escaped-var)
                    pat2 (.. "%(tset%s+" escaped-tset "%s+\"%s*" escaped-key "%s*\"%s+" escaped-var)]
                (var search-start 1)
                (while (and (not found) search-start)
                  (let [(start1 end1) (string.find fn-form pat1 search-start)]
                    (if start1
                        (if (>= start1 min-byte)
                            (set found true)
                            (set search-start (+ end1 1)))
                        (let [(start2 end2) (string.find fn-form pat2 search-start)]
                          (if start2
                              (if (>= start2 min-byte)
                                  (set found true)
                                  (set search-start (+ end2 1)))
                              (lua :break)))))))))
          found))))

(fn global-mutation-restoration-rule-run [ctx]
  (var diagnostics [])
  (each [_ ff (ipairs (or (. ctx.facts :files) []))]
    (when (string.find ff.path "/tests/" 1 true)
      ;; Step 1: collect max mutation line per (fn, path) group
      (var fn-path-max-line {})
      (each [_ mutation (ipairs (or ff.mutations []))]
        (when (mutation-path-is-sensitive? mutation.path)
          (let [fn-name (or mutation.enclosing-fn "<top-level>")
                path-text (table.concat (or mutation.path []) ".")
                key (.. fn-name "::" path-text)]
            (let [current-max (or (. fn-path-max-line key) 0)]
              (when (> mutation.line current-max)
                (tset fn-path-max-line key mutation.line))))))
      ;; Step 2: for each (fn, path) group, check restoration after max line
      (var diagnosed {})
      (each [key max-line (pairs fn-path-max-line)]
        (when (not (. diagnosed key))
          (let [sep (key:find "::" 1 true)]
            (when sep
              (let [fn-name (key:sub 1 (- sep 1))
                    path-text (key:sub (+ sep 2))]
                ;; Find the enclosing function form and its definition line
                (var fn-form nil)
                (var fn-def-line nil)
                (when (not= fn-name "<top-level>")
                  (each [_ def (ipairs (or ff.definitions []))]
                    (when (and (= def.kind :fn) (= def.name fn-name))
                      (set fn-form def.form)
                      (set fn-def-line def.line))))
                ;; Check restoration patterns (order-aware)
                (var has-restoration false)
                (when (and fn-form fn-def-line)
                  ;; Build path-segments from path-text
                  (local path-segments [])
                  (each [seg (path-text:gmatch "[^%.]+")]
                    (table.insert path-segments seg))
                  ;; Pattern 1: with-restored-app-fields (explicit)
                  (when (string.find fn-form "with-restored-app-fields" 1 true)
                    (set has-restoration true))
                  ;; Determine whether the mutation is inside a pcall body.
                  ;; When it is, the restore must be outside/after that specific
                  ;; pcall body (Pattern 3). When it is not, the standard
                  ;; line-based ordering check applies (Pattern 2).
                  (let [pcall-ranges (find-all-pcall-fn-ranges fn-form)
                        enclosing-pcall-end (find-enclosing-pcall-end-byte fn-form fn-def-line max-line pcall-ranges)]
                    ;; Pattern 2: direct snapshot table restore (order-aware)
                    ;; Only when the mutation is NOT inside a pcall body — if it
                    ;; is inside, Pattern 3 handles the pcall-specific ordering.
                    (when (and (not has-restoration) (not enclosing-pcall-end))
                      (when (has-concrete-restore-after-line? fn-form fn-def-line path-segments max-line)
                        (set has-restoration true)))
                    ;; Pattern 3: pcall cleanup restore (order-aware)
                    ;; The mutation is inside a pcall body, so the restore must be
                    ;; outside/after that specific pcall body's closing paren,
                    ;; not inside the protected mutation path.
                    (when (and (not has-restoration) enclosing-pcall-end)
                      (when (has-concrete-restore-after-byte? fn-form fn-def-line path-segments enclosing-pcall-end)
                        (set has-restoration true)))))
                ;; Emit diagnostic if no valid restoration found
                (when (not has-restoration)
                  (tset diagnosed key true)
                  (table.insert diagnostics
                    (Diagnostics.violation
                      {:constraint-id "lifecycle.global-mutation-restoration"
                       :family "test-isolation"
                       :message (.. "test file mutates sensitive global " path-text " without snapshot and restore")
                       :file ff.path :line max-line :column 0
                       :evidence {:global-path path-text :enclosing-fn fn-name}
                        :hint (.. "snapshot and restore " path-text " using with-restored-app-fields or pcall cleanup")}))))))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.global-mutation-restoration" :family "test-isolation" :targets [:repo] :kind :static :run global-mutation-restoration-rule-run :fn global-mutation-restoration-rule-run}])

M
