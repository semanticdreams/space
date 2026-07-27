;; Baseline module for experimental Fennel constraints.
;; Provides baseline policy: fingerprinting, suppression, worsened/stale/missing-required detection.

(local json (require :json))

(local M {})

(fn M.load []
  "Load baseline data from the versioned baseline-data module."
  (require :constraints.baseline-data))

(fn M.fingerprint [diagnostic]
  "Create a stable fingerprint string from a diagnostic's message and evidence.
  Fingerprints are deterministic JSON-encoded hashes of the violation signature."
  (json.dumps {:message (or diagnostic.message "")
               :evidence (or diagnostic.evidence {})}))

(fn table-contains? [tbl val]
  "Check whether a sequential table contains a value."
  (var found false)
  (each [_ v (ipairs tbl)]
    (when (= v val)
      (set found true)))
  found)

(fn make-key [constraint-id file line]
  "Build a lookup key from constraint-id, file, and line."
  (.. (or constraint-id "") "|" (or file "") "|" (tostring (or line 0))))

(fn M.apply [diagnostics baseline-data present-rule-ids]
  "Apply baseline policy to a list of diagnostics.
  baseline-data: {:required-rule-ids [string ...] :entries [baseline-entry ...]}
  baseline-entry: {:constraint-id :file :line :fingerprint :measure :reason}
  present-rule-ids: sequential table of rule IDs that executed.
  Returns {:diagnostics [any ...] :baseline-diagnostics [any ...]}.

  Policy:
  - Exact match (constraint-id + file + line + fingerprint) → suppressed.
  - Same location but higher evidence.measure → baseline.worsened emitted.
  - Baseline entry with no matching diagnostic → baseline.stale emitted.
  - Required rule ID not in present-rule-ids → baseline.required-rule-missing emitted.
  "
  (local out-diagnostics [])
  (local baseline-diagnostics [])
  (local entries (or baseline-data.entries []))
  (local required-ids (or baseline-data.required-rule-ids []))

  ;; Build a lookup from (constraint-id|file|line) → entry-indexed-by-fingerprint
  ;; Each value is a map from fingerprint to {:entry <entry> :index <i>}
  (local baseline-by-key {})
  (each [i entry (ipairs entries)]
    (let [key (make-key entry.constraint-id entry.file entry.line)]
      (when (not (. baseline-by-key key))
        (tset baseline-by-key key {}))
      (tset (. baseline-by-key key) entry.fingerprint {:entry entry :index i})))

  ;; Track which baseline entries were matched (by index → true)
  (local matched-entries {})

  ;; Process each current diagnostic
  (each [_ d (ipairs diagnostics)]
    (let [key (make-key d.constraint-id d.file d.line)
          fp (M.fingerprint d)
          entries-for-key (. baseline-by-key key)]
      (var suppressed false)
      (when entries-for-key
        ;; Check for exact fingerprint match → suppress
        (when (. entries-for-key fp)
          (set suppressed true)
          (tset matched-entries (. entries-for-key fp :index) true))
        ;; Check for worsened (same location, different fingerprint, higher measure)
        (when (not suppressed)
          (each [_ entry-info (pairs entries-for-key)]
            (let [entry entry-info.entry
                  baseline-measure (or entry.measure 0)
                  current-measure (or (. d.evidence :measure) 0)]
              (when (and (not= fp entry.fingerprint)
                         (> current-measure baseline-measure))
                (tset matched-entries entry-info.index true)
                (let [worsened-diag {:constraint-id d.constraint-id
                                     :family "baseline"
                                     :severity :error
                                     :message (.. "baseline violation worsened for "
                                                  d.constraint-id ": measure "
                                                  baseline-measure " → " current-measure)
                                     :evidence {:prev-measure baseline-measure
                                                :curr-measure current-measure}
                                     :hint (.. "update the baseline entry for "
                                               (or d.file "?") ":" (tostring (or d.line "?"))
                                               " or fix the violation")
                                     :file d.file
                                     :line d.line
                                     :worsened true}]
                  (when d.target
                    (tset worsened-diag :target d.target))
                  (table.insert baseline-diagnostics worsened-diag)))))))
      ;; Emit diagnostic unless suppressed
      (when (not suppressed)
        (table.insert out-diagnostics d))))

  ;; Check for stale baseline entries (entries not matched by any current diagnostic)
  (each [i entry (ipairs entries)]
    (when (not (. matched-entries i))
      (let [stale-diag {:constraint-id entry.constraint-id
                        :family "baseline"
                        :severity :error
                        :message (.. "baseline entry stale: " entry.constraint-id
                                     " at " (or entry.file "?") ":" (tostring (or entry.line "?")))
                        :evidence {:reason (or entry.reason "no matching violation found")}
                        :hint "remove the stale baseline entry or verify the violation still exists"
                        :file entry.file
                        :line entry.line
                        :stale true}]
        (table.insert baseline-diagnostics stale-diag))))

  ;; Check for missing required rules
  (each [_ required-id (ipairs required-ids)]
    (when (not (table-contains? present-rule-ids required-id))
      (let [missing-diag {:constraint-id required-id
                          :family "baseline"
                          :severity :error
                          :message (.. "required constraint missing: " required-id)
                          :evidence {}
                          :hint "restore the constraint rule implementation or remove it from required-rule-ids"
                          :missing-required true}]
        (table.insert baseline-diagnostics missing-diag))))

  {:diagnostics out-diagnostics
   :baseline-diagnostics baseline-diagnostics})

M
