;; Test-Isolation constraint rules for experimental Fennel constraints.
;; One rule: global-mutation-restoration

(local Diagnostics (require :constraints.diagnostics))
(local M {})

(local sensitive ["app.renderers" "app.lights" "app.engine" "app.activity-registry" "app.physics-containment-config" "package.loaded"])

;; Strip double-quoted string literals from form text so that pattern
;; matching does not produce false positives on string contents.
(fn strip-strings [s]
  (s:gsub "\"[^\"]*\"" ""))

;; Strip Fennel comments (; to end of line) from form text. Must be
;; called after strip-strings to avoid removing semicolons that appear
;; inside string literals.
(fn strip-comments [s]
  (local lines [])
  (each [line (s:gmatch "[^\n]*")]
    (local comment-pos (string.find line ";" 1 true))
    (if comment-pos
        (table.insert lines (string.sub line 1 (- comment-pos 1)))
        (table.insert lines line)))
  (table.concat lines "\n"))

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
  ;; Always checked regardless of whether literal covering snapshots were found,
  ;; so that mixed literal+variable-key snapshots are all collected (R2-1).
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
      (set first-unresolved-var snap-var)))
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
   Handles both vector literal and variable key arguments.
   Returns {:body-start body-start-byte} on success, nil on failure."
  (var inside nil)
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
                          (set inside {:body-start body-start})
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

(fn anon-byte-inside-with-restored-app-body? [parent-form anon-byte]
  "Check if the byte position in parent-form falls inside a
   with-restored-app wrapper body (past the fields key argument).
   Returns {:body-start body-start-byte} on success, nil on failure.
   Requires exact callee match: token must not be a substring of a
   longer identifier name (both leading and trailing boundaries)."
  (var inside nil)
  (var search-pos 1)
  (local token "with-restored-app")
  (local token-len (length token))
  (local id-char-pat "[%w%-_%?!%.]")
  (while (and (not inside) search-pos)
    (local token-start (string.find parent-form token search-pos true))
    (local after-pos (if token-start (+ token-start token-len) nil))
    (if (and token-start (< token-start anon-byte)
             ;; Leading boundary: byte before token must not be an
             ;; identifier character (prevents matching within longer
             ;; names like not-with-restored-app).
             (if (> token-start 1)
                 (not (string.find
                       (parent-form:sub (- token-start 1) (- token-start 1))
                       id-char-pat 1 false))
                 true)
             ;; Trailing boundary: byte after token must not be an
             ;; identifier character (prevents matching within longer
             ;; names like with-restored-app-extra).
             (if after-pos
                 (and (<= after-pos (length parent-form))
                      (not (string.find
                            (parent-form:sub after-pos after-pos)
                            id-char-pat 1 false)))
                 false))
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
                          (set inside {:body-start body-start})
                          (set search-pos (+ token-start token-len))))
                    (set search-pos (+ call-end 1))))
              (set search-pos (+ token-start token-len))))
        ;; Reject: no match, or token is part of a longer identifier
        (set search-pos (if token-start (+ token-start token-len) nil))))
  inside)

(fn has-valid-with-restored-app-def? [definitions]
  "Check if definitions includes a function named with-restored-app
   whose body matches restoring semantics: snapshots fields from app
   into snapshot table, runs (pcall f), then restores fields from
   snapshot back to app.
   Requires correct ordering: snapshot before (pcall f), restore after.
   Validates against concrete (set ...) assignment forms — does not
   accept raw operand substrings in non-assignment contexts (e.g. print).
   Strips string literals and comments before matching.
   Returns true only when all three ordered markers are present."
  (var defs definitions)
  (when (not defs) (set defs []))
  (var found false)
  (var di 1)
  (while (and (not found) (<= di (length defs)))
    (local def (. defs di))
    (when (and (= def.kind :fn) (= def.name "with-restored-app") def.form)
      ;; Strip string literals and comments so marker substrings in
      ;; non-code text cannot cause false positives.
      (local clean (strip-comments (strip-strings def.form)))
      ;; Find the (pcall f) position in the stripped form —
      ;; this is the ordering anchor.
      (local pcall-pos (string.find clean "(pcall f)" 1 true))
      (when pcall-pos
        ;; Check 1: snapshot-direction assignment BEFORE pcall
        ;; Must be an actual (set (. snapshot key) (. app key)) form
        ;; — not raw operands in print/other non-set contexts.
        ;; Lua pattern matches (set<ws>(.<ws>snapshot<ws>key)<ws>(.<ws>app<ws>key)
        ;; with flexible whitespace (including newlines) between tokens.
        (var has-snapshot false)
        (local snap-pat "%(set%s+%(%.%s*snapshot%s+key%)%s+%(%.%s*app%s+key%)")
        (local snap-pos (string.find clean snap-pat 1 false))
        (when (and snap-pos (< snap-pos pcall-pos))
          (set has-snapshot true))
        ;; Check 2: restore-direction assignment AFTER pcall
        ;; Must be an actual (set (. app key) (. snapshot key)) form.
        ;; Lua pattern matches (set<ws>(.<ws>app<ws>key)<ws>(.<ws>snapshot<ws>key)
        (var has-restore false)
        (local rest-pat "%(set%s+%(%.%s*app%s+key%)%s+%(%.%s*snapshot%s+key%)")
        (when (string.find clean rest-pat (+ pcall-pos 1) false)
          (set has-restore true))
        (when (and has-snapshot has-restore)
          (set found true))))
    (set di (+ di 1)))
  found)

(fn operand-is-path-prefix? [op path-text]
  "Check if op is a strict path prefix of path-text (followed by . or end)."
  (local ol (length op))
  (local pl (length path-text))
  (if (< pl ol) false
      (not (= (path-text:sub 1 ol) op)) false
      (> pl ol) (= (path-text:sub (+ ol 1) (+ ol 1)) ".")
      true))

(fn all-operands-are-prefixes? [operands path-text]
  "Check that all operands (except the last) are path prefixes of path-text."
  (var all-prefixes true)
  (for [i 1 (- (length operands) 1)]
    (when (and all-prefixes (not (operand-is-path-prefix? (. operands i) path-text)))
      (set all-prefixes false)))
  all-prefixes)

(fn check-and-operands [operands path-text]
  "Validate (and ...) operands: final operand must be exact path, all prior
   must be path-prefix guards. Returns true if valid."
  (local nops (length operands))
  (if (<= nops 0) false
      (not (= (. operands nops) path-text)) false
      (all-operands-are-prefixes? operands path-text)))

(fn try-and-snapshot-var [fn-form path-text]
  "Try to find a snapshot variable from a nil-guarded (and ...) form.
   Returns the variable name or nil. Supports both (local VAR (and ...)) and
   (let [VAR (and ...)] ...) patterns."
  (var snap-var nil)
  ;; Check (local VAR (and ...)) patterns
  (each [var-name and-body (fn-form:gmatch (.. "%(local%s+([^%s]+)%s+%(and%s+(.-)%)%s*%)"))]
    (when (not snap-var)
      (local operands [])
      (each [op (and-body:gmatch "[^%s]+")]
        (table.insert operands op))
      (when (check-and-operands operands path-text)
        (set snap-var var-name))))
  ;; Check (let [VAR (and ...)] ...) patterns
  (when (not snap-var)
    (each [var-name and-body (fn-form:gmatch (.. "%(let%s*%[%s*([^%s]+)%s+%(and%s+(.-)%)%s*%]"))]
      (when (not snap-var)
        (local operands [])
        (each [op (and-body:gmatch "[^%s]+")]
          (table.insert operands op))
        (when (check-and-operands operands path-text)
          (set snap-var var-name)))))
  snap-var)

(fn find-snapshot-var [fn-form path]
  "Find the first snapshot variable bound to the given path via let or local.
   Returns the variable name as a string, or nil if none found.
   Supports nil-guarded snapshots via (and guard1 ... guardN exact-path)."
  (local path-text (table.concat path "."))
  (local escaped-path (escape-pattern path-text))
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
  ;; Check (local VAR (and ...) ...) nil-guarded snapshots
  (when (not snap-var)
    (set snap-var (try-and-snapshot-var fn-form path-text)))
  snap-var)


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
   Compares start byte positions instead of line numbers, supporting
   same-line restore-before-mutation detection (R2-3)."
  (local snap-var (find-snapshot-var fn-form path))
  (if (not snap-var) false
      (do
        (local path-text (table.concat path "."))
        (local escaped-path (escape-pattern path-text))
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
            (local escaped-tset (escape-pattern tset-table))
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

(fn find-pcall-call-start [form-text pcall-byte]
  "Given the byte position of 'p' in 'pcall', find the opening '(' of the pcall call.
   Returns the byte position of '(' or nil."
  (var pos (- pcall-byte 1))
  (while (and (>= pos 1))
    (local ch (form-text:sub pos pos))
    (if (= ch "(") (lua "break")
        (= ch " ") (set pos (- pos 1))
        (= ch "\n") (set pos (- pos 1))
        (= ch "\t") (set pos (- pos 1))
        #(set pos nil)))
  (if (and pos (>= pos 1) (= (form-text:sub pos pos) "(")) pos nil))

(fn find-all-pcall-call-spans [form-text pcall-ranges]
  "Given a form text and pre-computed pcall fn-ranges, compute pcall CALL spans.
   Returns a list of {:call-start :call-end} for each pcall call.
   call-start is the '(' before 'pcall', call-end is the matching ')' via paren-matching."
  (var spans [])
  (each [_ range (ipairs pcall-ranges)]
    (var pcall-byte nil)
    ;; Find the 'pcall' text near this fn-start by searching backwards
    (for [search (- range.fn-start 2) (- range.fn-start 10) -1]
      (when (and (not pcall-byte) (>= search 1))
        (when (= (form-text:sub search (+ search 4)) "pcall")
          (set pcall-byte search))))
    (when pcall-byte
      (local call-start (find-pcall-call-start form-text pcall-byte))
      (when call-start
        (local call-end (find-matching-close form-text call-start))
        (when call-end
          (table.insert spans {:call-start call-start :call-end call-end})))))
  spans)

(fn find-enclosing-call-span [call-spans form-text form-line max-line]
  "Find which call span (if any) encloses the mutation position.
   Returns {:call-start :call-end} or nil."
  (local mutation-byte (find-mutation-approx-byte form-text form-line max-line))
  (var enclosing nil)
  (each [_ cs (ipairs call-spans)]
    (when (and (not enclosing) (<= cs.call-start mutation-byte) (>= cs.call-end mutation-byte))
      (set enclosing cs)))
  enclosing)

(fn scan-let-vec-for-binding [vec-content escaped-var]
  "Scan a let binding vector's content (text between [ and ]) for escaped-var
   at binding-name positions (even 0-indexed). Handles complex value
   expressions via paren/bracket/brace matching. Returns true iff
   escaped-var appears as a binding name."
  (var pos 1)
  (var is-name true)  ;; first token after [ is always a binding name
  (local slen (length vec-content))
  (var found false)
  (while (and (not found) (<= pos slen))
    ;; Skip leading whitespace
    (while (and (<= pos slen) (vec-content:find "^[%s\n]" pos))
      (set pos (+ pos 1)))
    (when (> pos slen) (lua "break"))
    ;; Determine where the current token ends
    (local ch (vec-content:sub pos pos))
    (local is-bracket (if (= ch "(") true (= ch "[") true (= ch "{") true false))
    (local token-end
      (if is-bracket
          (do
            (local close (find-matching-close vec-content pos))
            (if close (+ close 1) (+ slen 1)))
          (= ch "\"")
          (do
            (local eq (vec-content:find "\"" (+ pos 1) true))
            (if eq (+ eq 1) (+ slen 1)))
          ;; Simple token: identifier, number, keyword, etc.
          (do
            (local delim (vec-content:find "[%s%(%)%[%]%{%}\";]" (+ pos 1)))
            (if delim delim (+ slen 1)))))
    (local token (vec-content:sub pos (- token-end 1)))
    ;; Check for escaped-var match at binding-name positions
    (when (and is-name (not= token "&"))
      (when (token:find (.. "^" escaped-var "$"))
        (set found true)))
    ;; Advance past this token
    (set pos token-end)
    ;; Toggle name/value: & at a name position keeps the next position
    ;; as a name (rest arg). Otherwise alternate.
    (if (and is-name (= token "&"))
        (set is-name true)
        (set is-name (not is-name))))
  found)

(fn var-rebound-in-let? [between escaped-var]
  "Check if escaped-var appears as a binding NAME (not value) in any
   (let [bindings ...] ...) form within the text. Only matches at
   binding-name positions in the vector. Returns true iff the var
   is rebound via let."
  (var search-pos 1)
  (var found false)
  (while (and (not found) search-pos)
    (local let-start (between:find "%(let%s+%[" search-pos))
    (if (not let-start)
        (set search-pos nil)
        (do
          (local bracket-pos (between:find "%[" let-start))
          (local bracket-end (and bracket-pos (find-matching-close between bracket-pos)))
          (if (not bracket-end)
              (set search-pos (+ let-start 4))
              (do
                (local vec-content (between:sub (+ bracket-pos 1) (- bracket-end 1)))
                (if (scan-let-vec-for-binding vec-content escaped-var)
                    (set found true)
                    (set search-pos (+ bracket-end 1))))))))
  found)

(fn restore-valid-for-var? [fn-form min-byte restore-start escaped-var]
  "Returns true iff restore-start >= min-byte AND the snapshot variable
   escaped-var is NOT rebound (via local or let) in the text between
   min-byte and restore-start. If the variable was rebound, the restore
   is invalid — it captures a post-mutation value.
   Detects (local VAR ...) and (let [VAR ...] ...) rebindings.
   For let, only binding-name positions (even 0-indexed from '[')
   are treated as rebindings; the var appearing as a value for another
   name (e.g. (let [unused orig ...] ...)) does not invalidate the restore."
  (if (< restore-start min-byte) false
      (do
        (local between (fn-form:sub min-byte (- restore-start 1)))
        (local local-pat (.. "%(local%s+" escaped-var "%s+"))
        (local let-first-pat (.. "%(let%s+%[%s*" escaped-var "%s+"))
        (if (between:find local-pat) false
            (between:find let-first-pat) false
            (var-rebound-in-let? between escaped-var) false
            true))))

(fn has-restore-after-byte-for-var? [fn-form path snap-var min-byte]
  "Check for concrete restore evidence at a byte position >= min-byte
   for a specific snapshot variable (no re-derivation of snap-var).
   Compares start byte positions instead of line numbers.
   Rejects restores when snap-var is rebound between min-byte and the restore
   position (e.g. (local VAR ...) or (let [VAR ...] ...) after pcall)."
  (local path-text (table.concat path "."))
  (local escaped-path (escape-pattern path-text))
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
          (if (restore-valid-for-var? fn-form min-byte start escaped-var)
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
    (local escaped-tset (escape-pattern tset-table))
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
            (if (restore-valid-for-var? fn-form min-byte start1 escaped-var)
                (set found true)
                (set search-start (+ end1 1))))
          (do
            (local s-e2 (find-substring fn-form pat2 search-start))
            (if s-e2
                (do
                  (local start2 s-e2.start)
                  (local end2 s-e2.end)
                  (if (restore-valid-for-var? fn-form min-byte start2 escaped-var)
                      (set found true)
                      (set search-start (+ end2 1))))
                (set search-start nil))))))
  found)

(fn snapshot-before-pcall-and-restore-after? [parent-form path-segments path-text enclosing-span]
  "Check if the parent has a valid snapshot binding BEFORE the pcall call start
   and that exact snapshot variable is concretely restored AFTER the pcall call end.
   Searches only the text before the pcall for snapshot bindings. Uses the pre-pcall
   snap-var directly for the restore check — does NOT re-derive from the full form.
   Helper snapshots (snapshot-app-fields/restore-app-fields!) are conservatively
   unsupported in parent-pcall path."
  (local before-text (parent-form:sub 1 (- enclosing-span.call-start 1)))
  (local snap-var (find-snapshot-var before-text path-segments))
  (if (not snap-var) false
      (has-restore-after-byte-for-var? parent-form path-segments snap-var enclosing-span.call-end)))

(fn check-parent-pcall-restoration [ff fn-def-line anon-def-col path-text path-segments max-line]
  "Check if an anonymous fn inside a pcall has parent-scope snapshot/restore.
   Returns true if the parent function has snapshot BEFORE pcall + restore AFTER pcall."
  (local containing (find-containing-fn-defs ff.definitions fn-def-line anon-def-col))
  (if (<= (length containing) 1) false
      (do
        (local parent (. containing 2))
        (if (not (and parent.form parent.line)) false
            (do
              (local pcall-ranges (find-all-pcall-fn-ranges parent.form))
              (if (<= (length pcall-ranges) 0) false
                  (do
                    (local pcall-end (find-enclosing-pcall-end-byte parent.form parent.line max-line pcall-ranges))
                    (if (not pcall-end) false
                        (do
                          (local call-spans (find-all-pcall-call-spans parent.form pcall-ranges))
                          (local enclosing-span (find-enclosing-call-span call-spans parent.form parent.line max-line))
                          (if (not enclosing-span) false
                              (snapshot-before-pcall-and-restore-after? parent.form path-segments path-text enclosing-span)))))))))))

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

(fn check-keys-string-coverage [keys-str path-text]
  "Given a keys string (e.g. ':renderers :engine'), check if path-text is covered."
  (local app-key (if (path-text:match "^app%.") (path-text:sub 5) path-text))
  (var covers false)
  (each [k (keys-str:gmatch ":?([%w%-_]+)")]
    (when (and (not covers) (> (length k) 0))
      (if (= k app-key)
          (set covers true)
          (do
            (local ek (escape-pattern k))
            (when (app-key:find (.. "^" ek "%.") 1 false)
              (set covers true))))))
  covers)

(fn resolve-variable-keys-vector [form var-name definitions]
  "Try to resolve a variable to its literal vector binding.
   Scans for (local VAR [...]) or (let [VAR [...]] ...) in the form,
   or looks for a :local-kind definition matching var-name in definitions.
   Returns the keys string from the vector, or nil if unresolved."
  ;; Try in the form first
  (local local-pat (.. "%(local%s+" (escape-pattern var-name) "%s+%[(.-)%]%s*%)"))
  (local local-start (string.find form local-pat))
  (if local-start
      (do
        (var keys-str nil)
        (each [ks (form:gmatch local-pat)]
          (when (not keys-str) (set keys-str ks)))
        keys-str)
      (do
        (local let-pat (.. "%(let%s*%[.-" (escape-pattern var-name) "%s+%[(.-)%]"))
        (var keys-str2 nil)
        (each [ks (form:gmatch let-pat)]
          (when (not keys-str2) (set keys-str2 ks)))
        (if keys-str2
            keys-str2
            ;; Try module-level local definitions — only direct literal vector
            ;; bindings (e.g. (local VAR [...])), not computed expressions
            ;; containing vectors (e.g. (local VAR (compute-keys [...]))).
            (do
              (var found-keys nil)
              (var defs (if definitions definitions []))
              (each [_ def (ipairs defs)]
                (when (and (= def.kind :local) (= def.name var-name) def.form (not found-keys))
                  ;; Use same strict pattern as same-form check: must be direct literal binding
                  (each [ks (def.form:gmatch local-pat)]
                    (when (not found-keys) (set found-keys ks)))))
              found-keys)))))

(fn wrapper-covers-path? [form body-start path-text definitions]
  "Check if the with-restored-app-fields key argument (just before body-start)
   covers the given path-text (e.g. 'app.engine').
   body-start is the byte position of the wrapper body (after keys argument).
   definitions is an optional list of module-level definitions to resolve
   variable keys when they're not bound in the function form.
   Scans backwards from body-start to find the key argument.
   For literal vector keys, checks coverage directly.
   For variable keys, attempts to resolve the variable to a literal vector;
   returns false if the variable cannot be resolved (conservative)."
  (var key-arg-end (- body-start 1))
  (while (and (>= key-arg-end 1))
    (local ch (form:sub key-arg-end key-arg-end))
    (if (if (= ch " ") true (= ch "\n") true (= ch "\t") true false)
        (set key-arg-end (- key-arg-end 1))
        (lua :break)))
  (var key-arg-start nil)
  (local ch-end (form:sub key-arg-end key-arg-end))
  (if (= ch-end "]")
      ;; Literal vector: find opening [, extract keys, check coverage
      (do
        (var depth 0)
        (var i key-arg-end)
        (while (and (>= i 1) (not key-arg-start))
          (local c (form:sub i i))
          (if (= c "]") (set depth (+ depth 1))
              (= c "[") (do (set depth (- depth 1))
                            (when (= depth 0) (set key-arg-start i)))
              (= c "\"") (do
                           (local prev-q (form:find "\"" (- i 1) true))
                           (when prev-q (set i prev-q))))
          (set i (- i 1)))
        (if (not key-arg-start)
            false
            (do
              (local keys-str (form:sub (+ key-arg-start 1) (- key-arg-end 1)))
              (check-keys-string-coverage keys-str path-text))))
      ;; Variable/symbol key: try to resolve to literal vector
      (do
        ;; Extract the variable name (scan backwards from key-arg-end)
        (var sym-start key-arg-end)
        (while (and (>= sym-start 1))
          (local sc (form:sub sym-start sym-start))
          (if (string.find sc "[%w%-_%.]" 1 false)
              (set sym-start (- sym-start 1))
              (lua :break)))
        (set sym-start (+ sym-start 1))
        (local var-name (form:sub sym-start key-arg-end))
        (if (<= (length var-name) 0)
            false
            (do
              (local resolved-keys (resolve-variable-keys-vector form var-name definitions))
              (if resolved-keys
                  (check-keys-string-coverage resolved-keys path-text)
                  false))))))

(fn check-positions-inside-covering-wraf? [parent-form parent-line positions path-text definitions]
  "Check if every mutation position byte in parent-form is inside a
   with-restored-app-fields or with-restored-app body whose keys cover path-text.
   Returns true if all positions are covered, false otherwise.
   with-restored-app wrapper recognition is only active when the same file
   has a valid with-restored-app helper definition with restoring semantics."
  (var all-covered true)
  (var pi 1)
  (local has-wra (has-valid-with-restored-app-def? definitions))
  (while (and all-covered (<= pi (length positions)))
    (local pos (. positions pi))
    (local pos-byte (+ (find-mutation-approx-byte parent-form parent-line pos.line)
                       (math.max 0 (- pos.column 1))))
    (if (<= pos-byte (length parent-form))
        (do
          (local wraf-result (anon-byte-inside-wraf-body? parent-form pos-byte))
          (if wraf-result
              (when (not (wrapper-covers-path? parent-form wraf-result.body-start path-text definitions))
                (set all-covered false))
              (if has-wra
                  (do
                    (local wra-result (anon-byte-inside-with-restored-app-body? parent-form pos-byte))
                    (if wra-result
                        (when (not (wrapper-covers-path? parent-form wra-result.body-start path-text definitions))
                          (set all-covered false))
                        (set all-covered false)))
                  (set all-covered false))))
        (set all-covered false))
    (set pi (+ pi 1)))
  all-covered)

(fn check-any-parent-wrapper [ff fn-def-line anon-def-col positions path-text max-line max-col]
  "Fallback: scan all fn definitions in the file to find any parent function
   whose form text contains a with-restored-app-fields wrapper that covers
   the actual mutation positions and the mutated path.
   Requires candidate definitions to actually contain the mutation line
   (computed from form newline count) to prevent false suppression from
   unrelated earlier wrappers."
  (var found false)
  (var di 1)
  (var defs ff.definitions)
  (when (not defs) (set defs []))
  (while (and (not found) (<= di (length defs)))
    (local def (. defs di))
    (when (and (= def.kind :fn) def.form (> max-line def.line))
      ;; Verify line containment: the candidate form must extend to max-line
      (var form-nls 0)
      (each [_ _ (def.form:gmatch "\n")] (set form-nls (+ form-nls 1)))
      (local def-end-line (+ def.line form-nls))
      (when (<= max-line def-end-line)
        (when (check-positions-inside-covering-wraf? def.form def.line positions path-text ff.definitions)
          (set found true))))
    (set di (+ di 1)))
  found)

(fn check-parent-wrapper [ff fn-def-line anon-def-col positions path-text max-line max-col]
  "Check Pattern 3: parent function wrapper for anonymous functions.
   Returns true if the actual mutation positions are inside a
   with-restored-app-fields body in any containing parent function,
   AND the wrapper key argument includes the mutated path-text field."
  (local search-col (if anon-def-col anon-def-col nil))
  (local containing (find-containing-fn-defs ff.definitions fn-def-line search-col))
  (if (<= (length containing) 1)
      (check-any-parent-wrapper ff fn-def-line anon-def-col positions path-text max-line max-col)
      (do
        (var found-restored false)
        (var pi 2)
        (while (and (not found-restored) (<= pi (length containing)))
          (local parent (. containing pi))
          (when (check-positions-inside-covering-wraf? parent.form parent.line positions path-text ff.definitions)
            (set found-restored true))
          (set pi (+ pi 1)))
        (if found-restored true
            (check-any-parent-wrapper ff fn-def-line anon-def-col positions path-text max-line max-col)))))

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

(fn all-positions-inside-covering-wrapper? [fn-form fn-def-line positions path-text definitions]
  "Check if every mutation position is inside a with-restored-app-fields
   or with-restored-app body whose key argument covers the given path-text.
   with-restored-app recognition only activates when the same file has
   a valid with-restored-app helper definition.
   Returns false if any mutation position is outside a covering wrapper."
  (var all-inside true)
  (local has-wra (has-valid-with-restored-app-def? definitions))
  (each [_ pos (ipairs positions)]
    (when all-inside
      (local pos-byte (+ (find-mutation-approx-byte fn-form fn-def-line pos.line)
                         (math.max 0 (- pos.column 1))))
       (local wraf-result (anon-byte-inside-wraf-body? fn-form pos-byte))
       (if wraf-result
           (when (not (wrapper-covers-path? fn-form wraf-result.body-start path-text definitions))
             (set all-inside false))
           (if has-wra
               (do
                 (local wra-result (anon-byte-inside-with-restored-app-body? fn-form pos-byte))
                 (if wra-result
                     (when (not (wrapper-covers-path? fn-form wra-result.body-start path-text definitions))
                       (set all-inside false))
                     (set all-inside false)))
               (set all-inside false)))))
  all-inside)

(fn compute-max-position [positions]
  "Find the maximum (line, column) position from a list of mutation positions."
  (var max-line 0)
  (var max-col 0)
  (each [_ pos (ipairs positions)]
    (when (if (> pos.line max-line) true
              (and (= pos.line max-line) (> pos.column max-col)) true
              false)
      (set max-line pos.line)
      (set max-col pos.column)))
  {:line max-line :column max-col})

(fn check-mutation-restoration [ff fn-form fn-def-line fn-name path-text positions max-line max-col anon-def-col]
  "Check all restoration patterns for a single mutation group.
   Returns true if the mutation is properly restored."
  (var has-restoration false)
  (when (is-test-infrastructure-fn? ff.path fn-name)
    (set has-restoration true))
  (local path-segments [])
  (each [seg (path-text:gmatch "[^%.]+")]
    (table.insert path-segments seg))
  (local min-byte (+ (find-mutation-approx-byte fn-form fn-def-line max-line)
                      (math.max 0 (- max-col 1))))
  (when (and (not has-restoration) (all-positions-inside-covering-wrapper? fn-form fn-def-line positions path-text ff.definitions))
    (set has-restoration true))
  (when (and (not has-restoration) (= fn-name "<anonymous>"))
    (when (check-parent-wrapper ff fn-def-line anon-def-col positions path-text max-line max-col)
      (set has-restoration true)))
  (local pcall-ranges (find-all-pcall-fn-ranges fn-form))
  (local enclosing-pcall-end (find-enclosing-pcall-end-byte fn-form fn-def-line max-line pcall-ranges))
  (when (and (not has-restoration) (not enclosing-pcall-end))
    (when (has-concrete-restore-after-byte? fn-form fn-def-line path-segments min-byte)
      (set has-restoration true)))
  (when (and (not has-restoration) (not enclosing-pcall-end))
    (when (has-helper-restore-after-byte? fn-form path-text min-byte)
      (set has-restoration true)))
  (when (and (not has-restoration) enclosing-pcall-end)
    (when (has-concrete-restore-after-byte? fn-form fn-def-line path-segments enclosing-pcall-end)
      (set has-restoration true)))
  (when (and (not has-restoration) enclosing-pcall-end)
    (when (has-helper-restore-after-byte? fn-form path-text enclosing-pcall-end)
      (set has-restoration true)))
  ;; Parent-scope pcall restoration: when the anonymous fn form lacks
  ;; snapshot/restore (because they're in the parent), check the parent
  ;; function's form for snapshot before pcall + restore after pcall.
  (when (and (not has-restoration) (= fn-name "<anonymous>"))
    (when (check-parent-pcall-restoration ff fn-def-line anon-def-col path-text path-segments max-line)
      (set has-restoration true)))
  has-restoration)

(fn global-mutation-restoration-rule-run [ctx]
  (var diagnostics [])
  (var files (. ctx.facts :files))
  (when (not files) (set files []))
  (each [_ ff (ipairs files)]
    (when (string.find ff.path "/tests/" 1 true)
      ;; Step 1: collect all mutation positions per (concrete fn, path) group
      (var fn-path-positions {})
      (var mutations ff.mutations)
      (when (not mutations) (set mutations []))
      (each [_ mutation (ipairs mutations)]
        (when (mutation-path-is-sensitive? mutation.path)
          (local key (build-mutation-group-key mutation ff))
          (local col (if mutation.column mutation.column 1))
          (when (not (. fn-path-positions key))
            (tset fn-path-positions key []))
          (table.insert (. fn-path-positions key) {:line mutation.line :column col})))
      ;; Step 2: for each (fn, path) group, check restoration for all mutation positions
      (var diagnosed {})
      (each [key positions (pairs fn-path-positions)]
        (local info (compute-max-position positions))
        (local max-line info.line)
        (local max-col info.column)
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
              (set has-restoration
                   (check-mutation-restoration ff fn-form fn-def-line fn-name path-text positions max-line max-col anon-def-col)))
            ;; Emit diagnostic if no valid restoration found
            (when (not has-restoration)
              (emit-mutation-diagnostic diagnostics diagnosed key ff path-text max-line fn-name)))))))
  (if (> (length diagnostics) 0) diagnostics nil))

(fn M.rules []
  [{:id "lifecycle.global-mutation-restoration" :family "test-isolation" :targets [:repo] :kind :static :run global-mutation-restoration-rule-run :fn global-mutation-restoration-rule-run}])

M
