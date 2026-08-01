(local M {})

(fn normalize-output-mode [mode]
  (if (= mode "json")
      :json
      (= mode :json)
      :json
      (= mode "summary")
      :summary
      (= mode :summary)
      :summary
      nil))

(fn M.split-output-argv [argv default-output]
  (local source (if argv argv []))
  (local default-mode (normalize-output-mode default-output))
  (assert default-mode "default output must be json or summary")
  (local filtered [])
  (var output default-mode)
  (var error nil)
  (var index 1)
  (while (<= index (# source))
    (local item (. source index))
    (if (= item "--output")
        (do
          (local raw-mode (. source (+ index 1)))
          (local mode (normalize-output-mode raw-mode))
          (if (not raw-mode)
              (do
                (set error "--output requires json or summary")
                (set output default-mode))
              (not mode)
              (do
                (set error "--output must be json or summary")
                (set output default-mode))
              true
              (set output mode))
          (set index (+ index 2)))
        (do
          (table.insert filtered item)
          (set index (+ index 1)))))
  {:argv filtered
   :output (if error default-mode output)
   :error error})

(fn plural [count singular plural-word]
  (if (= count 1) singular plural-word))

(fn location [diagnostic]
  (local file (if diagnostic.file diagnostic.file ""))
  (local line diagnostic.line)
  (local column diagnostic.column)
  (if (and (> (# file) 0) line column)
      (.. file ":" line ":" column)
      (and (> (# file) 0) line)
      (.. file ":" line)
      (> (# file) 0)
      file
      "<unknown>"))

(fn diagnostic-lines [diagnostics limit]
  (local lines [])
  (local max-count (if limit limit 5))
  (var index 1)
  (while (and (<= index (# diagnostics)) (<= index max-count))
    (local diagnostic (. diagnostics index))
    (local message (if diagnostic.message diagnostic.message "diagnostic"))
    (table.insert lines (.. "- " (location diagnostic) " " (tostring message)))
    (when diagnostic.hint
      (table.insert lines (.. "  hint: " (tostring diagnostic.hint))))
    (set index (+ index 1)))
  (when (> (# diagnostics) max-count)
    (table.insert lines (.. "- ... " (- (# diagnostics) max-count) " more diagnostics")))
  lines)

(fn M.fennel-check-summary [result]
  (local summary (if result.summary result.summary {}))
  (local checked (if summary.checked summary.checked 0))
  (local failed (if summary.failed summary.failed 0))
  (local status (if result.status result.status (if result.ok :pass :fail)))
  (local diagnostics (if result.diagnostics result.diagnostics []))
  (local lines [(if result.ok
                    (.. "fennel-check: pass (checked " checked " " (plural checked "file" "files") ")")
                    (.. "fennel-check: " status " (checked " checked " " (plural checked "file" "files")
                        ", " failed " failed)"))])
  (when (not result.ok)
    (each [_ line (ipairs (diagnostic-lines diagnostics 5))]
      (table.insert lines line))
    (table.insert lines "rerun with --output json for full diagnostics"))
  (table.concat lines "\n"))

(fn M.constraints-summary [result]
  (local status (if result.status result.status :fail))
  (local counts (if result.counts result.counts {}))
  (local total (if counts.total counts.total 0))
  (local diagnostics (if result.diagnostics result.diagnostics []))
  (local lines [(.. "constraints: " status " (" total " " (plural total "diagnostic" "diagnostics") ")")])
  (when (not= status :pass)
    (each [_ line (ipairs (diagnostic-lines diagnostics 5))]
      (table.insert lines line))
    (table.insert lines "rerun with --output json for full diagnostics"))
  (table.concat lines "\n"))

{:split-output-argv M.split-output-argv
 :fennel-check-summary M.fennel-check-summary
 :constraints-summary M.constraints-summary}
