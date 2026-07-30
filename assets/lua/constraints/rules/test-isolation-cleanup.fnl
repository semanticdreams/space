;; Cleanup-closure restore helpers for test-isolation constraint.
;; Extracted to keep main rule module under the 1200-line limit.

(local M {})

(fn find-actual-child-occurrence [find-line-byte parent-form parent-line child-fn-form child-fn-line child-fn-col mutation-line mutation-col]
  (local child-byte (+ (find-line-byte parent-form parent-line child-fn-line)
                       (math.max 0 (- (if child-fn-col child-fn-col 1) 1))))
  (local mutation-byte (+ (find-line-byte parent-form parent-line mutation-line)
                          (math.max 0 (- (if mutation-col mutation-col 1) 1))))
  (var containing nil)
  (var search-start 1)
  (while search-start
    (local start-byte (string.find parent-form child-fn-form search-start true))
    (if (not start-byte)
        (set search-start nil)
        (do
          (local end-byte (+ start-byte (length child-fn-form) -1))
          (when (= start-byte child-byte) (lua "return start_byte"))
          (when (and (not containing) (<= start-byte mutation-byte) (<= mutation-byte end-byte))
            (set containing start-byte))
          (set search-start (+ start-byte 1)))))
  containing)

(fn check-parent-child-mutation-pcall-restoration* [deps ff child-fn-form child-fn-line anon-def-col path-segments mutation-line mutation-col]
  (local containing (deps.find-containing-fn-defs ff.definitions child-fn-line anon-def-col))
  (when (<= (length containing) 1) (lua "return false"))
  (local parent (. containing 2))
  (when (not (and parent.form parent.line child-fn-form)) (lua "return false"))
  (local child-start (find-actual-child-occurrence deps.find-mutation-approx-byte parent.form parent.line child-fn-form child-fn-line anon-def-col mutation-line mutation-col))
  (when (not child-start) (lua "return false"))
  (local child-end (+ child-start (length child-fn-form) -1))
  (local before-child (parent.form:sub 1 (- child-start 1)))
  (local snap-var (deps.find-snapshot-var before-child path-segments))
  (when (not snap-var) (lua "return false"))
  (local assigned-init-renderers? (string.find before-child "%(set%s+AppBootstrap%.init%-renderers%s*$" 1 false))
  (when (not assigned-init-renderers?) (lua "return false"))
  (var restored false)
  (local pcall-ranges (deps.find-all-pcall-fn-ranges parent.form))
  (local call-spans (deps.find-all-pcall-call-spans parent.form pcall-ranges))
  (each [i span (ipairs call-spans)]
    (when (and (not restored) (> span.call-start child-start))
      (local between (parent.form:sub (+ child-end 1) (- span.call-start 1)))
      (local range (. pcall-ranges i))
      (local body (if range (parent.form:sub range.fn-start range.fn-end) ""))
      (local main-init? (if (string.find body "Main.init" 1 true) true
                            (string.find body "Main :init" 1 true) true
                            (string.find body "Main:init" 1 true) true
                            false))
      (when (and (not (string.find between "init-renderers" 1 true))
                 main-init?
                 (deps.has-restore-after-byte-for-var? parent.form path-segments snap-var span.call-end))
        (set restored true))))
  restored)

(tset M :make-helpers
  (fn [deps]
    "Create cleanup helpers with injected dependencies from parent module."
    (local find-containing-fn-defs deps.find-containing-fn-defs)
    (local find-snapshot-var deps.find-snapshot-var)
    (local escape-pattern deps.escape-pattern)
    (local find-all-pcall-fn-ranges deps.find-all-pcall-fn-ranges)
    (local find-all-pcall-call-spans deps.find-all-pcall-call-spans)
    (local has-restore-after-byte-for-var? deps.has-restore-after-byte-for-var?)

    (fn find-matching-close [text open-pos]
      (local open-ch (text:sub open-pos open-pos))
      (local close-ch (if (= open-ch "(") ")" (= open-ch "[") "]" (= open-ch "{") "}"))
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

    (fn blank-nested-scope-forms [text]
      (var result text)
      (var search-pos 1)
      ;; Patterns to match, with their byte-length skip values.
      ;; λ is 2 bytes in UTF-8, so (λ is 4 bytes total.
      (local scope-pats [["(fn " 4] ["(lambda " 8] ["(λ " 4]])
      (while search-pos
        (var best-start nil)
        (var best-skip 0)
        (each [_ [pat skip] (ipairs scope-pats)]
          (local pos (string.find result pat search-pos true))
          (when (and pos (if (not best-start) true (< pos best-start) true false))
            (set best-start pos)
            (set best-skip skip)))
        (if best-start
            (if (= best-start 1)
                ;; Parent function header — skip, do not blank
                (set search-pos (+ best-start best-skip))
                (do
                  (local body-start (+ best-start best-skip))
                  (local close (find-matching-close result best-start))
                  (if close
                      (do
                        (local before (result:sub 1 (- body-start 1)))
                        (local after (result:sub (+ close 1)))
                        (var blanked "")
                        (for [i body-start close]
                          (set blanked (.. blanked " ")))
                        (set result (.. before blanked after))
                        (set search-pos (+ best-start best-skip)))
                      (set search-pos (+ best-start best-skip)))))
            (set search-pos nil)))
      result)

    (fn find-snapshot-var-before-byte [parent-form path-text max-byte]
      (local raw-before-text (parent-form:sub 1 (- max-byte 1)))
      ;; Blank nested scope-form bodies so sibling-scope locals are not
      ;; misread as parent-scope snapshot bindings (R1-1).
      (local before-text (blank-nested-scope-forms raw-before-text))
      (local segments [])
      (each [seg (path-text:gmatch "[^%.]+")] (table.insert segments seg))
      (find-snapshot-var before-text segments))

    (fn mutation-form-is-restore-assignment? [mutation-form path-text snap-var]
      (local escaped-path (escape-pattern path-text))
      (local escaped-var (escape-pattern snap-var))
      (local set-pat (.. "^%(set%s+" escaped-path "%s+" escaped-var "%s*%)"))
      (when (string.find mutation-form set-pat) (lua "return true"))
      (local segments [])
      (each [seg (path-text:gmatch "[^%.]+")] (table.insert segments seg))
      (when (< (length segments) 2) (lua "return false"))
      (local plen (length segments))
      (local table-parts [])
      (for [i 1 (- plen 1)] (table.insert table-parts (. segments i)))
      (local tset-table (table.concat table-parts "."))
      (local key (. segments plen))
      (local escaped-tset (escape-pattern tset-table))
      (local escaped-key (escape-pattern key))
      (local pat1 (.. "^%(tset%s+" escaped-tset "%s+:%s*" escaped-key "%s+" escaped-var "%s*%)"))
      (local pat2 (.. "^%(tset%s+" escaped-tset "%s+\"%s*" escaped-key "%s*\"%s+" escaped-var "%s*%)"))
      (if (string.find mutation-form pat1) true
          (string.find mutation-form pat2) true
          false))

    (fn check-parent-snapshot-child-restore [ff child-fn-form child-fn-name child-fn-line path-text]
      (local defs (if ff.definitions ff.definitions []))
      (local containing (find-containing-fn-defs defs child-fn-line))
      (when (<= (length containing) 1) (lua "return false"))
      (local parent (. containing 2))
      (when (not (and parent.form parent.line)) (lua "return false"))
      (when (= parent.name "<anonymous>") (lua "return false"))
      (local child-start-byte (string.find parent.form child-fn-form 1 true))
      (when (not child-start-byte) (lua "return false"))
      (local snap-var (find-snapshot-var-before-byte parent.form path-text child-start-byte))
      (when (not snap-var) (lua "return false"))
      (var all-restore true)
      (var muts ff.mutations)
      (when (not muts) (set muts []))
      (each [_ mutation (ipairs muts)]
        (when all-restore
          (local mpath-text (table.concat (if mutation.path mutation.path []) "."))
          (when (= mpath-text path-text)
            (when (= mutation.enclosing-fn child-fn-name)
              (when (not (mutation-form-is-restore-assignment? mutation.form path-text snap-var))
                (set all-restore false))))))
      all-restore)

    (fn check-parent-child-mutation-pcall-restoration [ff child-fn-form child-fn-line anon-def-col path-segments mutation-line mutation-col]
      (check-parent-child-mutation-pcall-restoration* deps ff child-fn-form child-fn-line anon-def-col path-segments mutation-line mutation-col))

    {:check-parent-snapshot-child-restore check-parent-snapshot-child-restore
     :check-parent-child-mutation-pcall-restoration check-parent-child-mutation-pcall-restoration}))

M
