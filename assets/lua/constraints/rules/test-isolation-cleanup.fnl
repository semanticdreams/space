;; Cleanup-closure restore helpers for test-isolation constraint.
;; Extracted to keep main rule module under the 1200-line limit.

(local M {})

(tset M :make-helpers
  (fn [deps]
    "Create cleanup helpers with injected dependencies from parent module."
    (local find-containing-fn-defs deps.find-containing-fn-defs)
    (local find-snapshot-var deps.find-snapshot-var)
    (local escape-pattern deps.escape-pattern)

    (fn find-matching-close [text open-pos]
      "Find matching close paren for an opener at open-pos. Returns byte or nil."
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

    (fn blank-nested-fns [text]
      "Replace nested (fn ...) form bodies with whitespace so sibling-scope
       locals are not misread as parent-scope snapshots. The first (fn ...)
       at position 1 is the parent header — skip it."
      (var result text)
      (var search-pos 1)
      (while search-pos
        (local fn-start (string.find result "(fn " search-pos true))
        (if fn-start
            (if (= fn-start 1)
                ;; Parent function header — skip, do not blank
                (set search-pos (+ fn-start 4))
                (do
                  ;; Nested fn — blank its body
                  (local body-start (+ fn-start 4))
                  (local close (find-matching-close result fn-start))
                  (if close
                      (do
                        (local before (result:sub 1 (- body-start 1)))
                        (local after (result:sub (+ close 1)))
                        (var blanked "")
                        (for [i body-start close]
                          (set blanked (.. blanked " ")))
                        (set result (.. before blanked after))
                        (set search-pos (+ fn-start 4)))
                      (set search-pos (+ fn-start 4)))))
            (set search-pos nil)))
      result)

    (fn find-snapshot-var-before-byte [parent-form path-text max-byte]
      (local raw-before-text (parent-form:sub 1 (- max-byte 1)))
      ;; Blank nested fn bodies so sibling-scope locals are not
      ;; misread as parent-scope snapshot bindings (R1-1).
      (local before-text (blank-nested-fns raw-before-text))
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

    {:check-parent-snapshot-child-restore check-parent-snapshot-child-restore}))

M
