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

{:split-output-argv M.split-output-argv}
