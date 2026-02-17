(local process (require :process))

(fn is-array? [value]
  (if (not (= (type value) :table))
      false
      (do
        (var max 0)
        (var count 0)
        (each [k _ (pairs value)]
          (if (or (not (= (type k) :number))
                  (not (= k (math.floor k)))
                  (< k 1))
              (lua "return false")
              (do
                (set count (+ count 1))
                (when (> k max)
                  (set max k)))))
        (= count max))))

(fn assert-string-array [name value]
  (when (not (is-array? value))
    (error (.. "ripgrep " name " must be an array")))
  (each [_ entry (ipairs value)]
    (when (not (= (type entry) :string))
      (error (.. "ripgrep " name " entries must be strings")))))

(fn trim-line-ending [text]
  (if (and text (> (# text) 0) (= (string.sub text -1) "\n"))
      (string.sub text 1 -2)
      text))

(fn parse-vimgrep-output [stdout]
  (local matches [])
  (each [line (string.gmatch stdout "[^\n]+")]
    (local (path line-number column text) (string.match line "^(.-):(%d+):(%d+):(.*)$"))
    (when path
      (table.insert matches {:path path
                             :line (tonumber line-number)
                             :column (tonumber column)
                             :text (trim-line-ending (or text ""))
                             :start 0
                             :end 0})))
  matches)

(fn build-args [opts]
  (local options (or opts {}))
  (local query options.query)
  (when (or (not (= (type query) :string)) (= (# query) 0))
    (error "ripgrep.search requires a non-empty :query string"))
  (local program (or options.program "rg"))
  (local args [program])
  (local program-args (or options.program-args []))
  (assert-string-array ":program-args" program-args)
  (each [_ arg (ipairs program-args)]
    (table.insert args arg))
  (table.insert args "--vimgrep")
  (table.insert args "--color")
  (table.insert args "never")

  (if (= options.case :ignore)
      (table.insert args "--ignore-case")
      (= options.case :sensitive)
      (table.insert args "--case-sensitive")
      (table.insert args "--smart-case"))

  (when options.hidden
    (table.insert args "--hidden"))
  (when options.literal
    (table.insert args "--fixed-strings"))
  (when options.follow
    (table.insert args "--follow"))
  (when options.word-regexp
    (table.insert args "--word-regexp"))

  (when options.max-count
    (when (or (not (= (type options.max-count) :number)) (< options.max-count 1))
      (error "ripgrep :max-count must be a positive number"))
    (table.insert args "--max-count")
    (table.insert args (tostring options.max-count)))

  (when options.max-filesize
    (when (not (= (type options.max-filesize) :string))
      (error "ripgrep :max-filesize must be a string (e.g. '1M')"))
    (table.insert args "--max-filesize")
    (table.insert args options.max-filesize))

  (when options.globs
    (assert-string-array ":globs" options.globs)
    (each [_ glob (ipairs options.globs)]
      (table.insert args "--glob")
      (table.insert args glob)))

  (table.insert args "--")
  (table.insert args query)

  (local paths (or options.paths ["."]))
  (assert-string-array ":paths" paths)
  (each [_ path (ipairs paths)]
    (table.insert args path))

  {:args args
   :cwd options.cwd
   :timeout options.timeout
   :query query
   :paths paths})

(fn build-result [run-spec process-result cancelled]
  (local parsed-matches
    (if (and (or (= process-result.exit-code 0)
                 (= process-result.exit-code 1))
             (not process-result.timed-out)
             (> (# process-result.stdout) 0))
        (parse-vimgrep-output process-result.stdout)
        []))
  (local ok
    (and (not process-result.timed-out)
         (not cancelled)
         (or (= process-result.exit-code 0)
             (= process-result.exit-code 1))))
  {:ok ok
   :cancelled (not (not cancelled))
   :exit-code process-result.exit-code
   :timed-out process-result.timed-out
   :stderr process-result.stderr
   :stdout process-result.stdout
   :matches parsed-matches
   :query run-spec.query
   :paths run-spec.paths})

(fn available? [opts]
  (local options (or opts {}))
  (local result (process.run {:args [(or options.program "rg") "--version"]
                              :cwd options.cwd
                              :timeout (or options.timeout 2)}))
  (= result.exit-code 0))

(fn search [opts]
  (local run-spec (build-args opts))
  (local result (process.run {:args run-spec.args
                              :cwd run-spec.cwd
                              :timeout run-spec.timeout}))
  (build-result run-spec result false))

(fn search-async [opts callback]
  (when (not (= (type callback) :function))
    (error "ripgrep.search-async requires a callback"))
  (local run-spec (build-args opts))
  (local token {:id nil
                :done false
                :cancelled false
                :callback callback})
  (set token.cancel
       (fn [self cancel-opts]
         (local options (or cancel-opts {}))
         (local signal (or options.signal 15))
         (local suppress-callback (if (= options.suppress-callback nil) false options.suppress-callback))
         (when suppress-callback
           (set self.callback nil))
         (if self.done
             false
             (do
               (set self.cancelled true)
               (if self.id
                   (process.kill self.id signal)
                   false)))))
  (set token.running
       (fn [self]
         (if self.id
             (process.running self.id)
             false)))
  (local id
    (process.spawn {:args run-spec.args
                    :cwd run-spec.cwd
                    :timeout run-spec.timeout}
                   (fn [result]
                     (when (not token.done)
                       (set token.done true)
                       (local out (build-result run-spec result token.cancelled))
                       (local cb token.callback)
                       (set token.callback nil)
                       (when cb
                         (cb out))))))
  (set token.id id)
  token)

{:available? available?
 :search search
 :search-async search-async}
