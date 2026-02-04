;; Minimal CLI argument parser with usage/help generation.
(local string string)
(local table table)
(local math math)

(fn normalize-key [key]
  (if (not key)
      nil
      (if (= (type key) "string")
          key
          (tostring key))))

(fn default-metavar [key]
  (if (not key)
      "VALUE"
      (do
        (local upper (string.upper (tostring key)))
        (string.gsub upper "-" "_"))))

(fn option-label [opt]
  (local parts [])
  (when opt.short
    (table.insert parts (.. "-" opt.short)))
  (when opt.long
    (table.insert parts (.. "--" opt.long)))
  (local label (table.concat parts ", "))
  (if opt.takes-value?
      (.. label " " (or opt.metavar (default-metavar opt.key)))
      label))

(fn positional-label [pos]
  (var label (or pos.metavar (default-metavar pos.key)))
  (if pos.repeatable?
      (set label (.. label "...")))
  (if pos.required?
      label
      (.. "[" label "]")))

(fn join-lines [lines]
  (table.concat lines "\n"))

(fn format-help [opt]
  (var help (or opt.help ""))
  (when opt.hint
    (if (= help "")
        (set help opt.hint)
        (set help (.. help " " opt.hint))))
  (when (not (= opt.default nil))
    (local default-str (tostring opt.default))
    (if (= help "")
        (set help (.. "Default: " default-str))
        (set help (.. help " (default: " default-str ")"))))
  help)

(fn build-usage [spec options positionals]
  (local name (or spec.name "app"))
  (local usage [(.. "usage: " name)])
  (when (> (length options) 0)
    (table.insert usage "[options]"))
  (each [_ pos (ipairs positionals)]
    (table.insert usage (positional-label pos)))
  (local lines [(table.concat usage " ")])
  (when spec.summary
    (table.insert lines "")
    (table.insert lines spec.summary))
  (when spec.description
    (table.insert lines "")
    (table.insert lines spec.description))
  (when (> (length options) 0)
    (table.insert lines "")
    (table.insert lines "Options:"))
  (var max-label 0)
  (each [_ opt (ipairs options)]
    (local label (option-label opt))
    (set max-label (math.max max-label (string.len label))))
  (each [_ opt (ipairs options)]
    (local label (option-label opt))
    (local padding (string.rep " " (+ 2 (- max-label (string.len label)))))
    (table.insert lines (.. "  " label padding (format-help opt))))
  (when (> (length positionals) 0)
    (table.insert lines "")
    (table.insert lines "Arguments:"))
  (each [_ pos (ipairs positionals)]
    (local label (or pos.metavar (default-metavar pos.key)))
    (local help (or pos.help ""))
    (table.insert lines (.. "  " label "  " help)))
  (when spec.epilog
    (table.insert lines "")
    (table.insert lines spec.epilog))
  (join-lines lines))

(fn in-list? [value items]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item value)
      (set found true)))
  found)

(fn parse-bool [value]
  (if (= (type value) "boolean")
      {:ok true :value value}
      (= (type value) "number")
      {:ok true :value (not (= value 0))}
      (do
        (local lower (string.lower (tostring value)))
        (if (in-list? lower ["true" "1" "yes" "on"])
            {:ok true :value true}
            (in-list? lower ["false" "0" "no" "off"])
            {:ok true :value false}
            {:ok false :error (.. "invalid boolean value: " (tostring value))}))))

(fn parse-value [spec raw]
  (var value raw)
  (var err nil)
  (when spec.type
    (if (= spec.type "int")
        (do
          (local num (tonumber raw))
          (if (or (= num nil) (not (= num (math.floor num))))
              (set value {:error (.. "expected integer for " spec.key)})
              (set value num)))
        (if (= spec.type "number")
            (do
              (local num (tonumber raw))
              (if (= num nil)
                  (set value {:error (.. "expected number for " spec.key)})
                  (set value num)))
            (if (= spec.type "bool")
                (do
                  (local parsed (parse-bool raw))
                  (if parsed.ok
                      (set value parsed.value)
                      (set value {:error parsed.error})))
                nil))))
  (when (and (= (type value) "table") value.error)
    (set err value.error))
  (when (and (not err) spec.parse)
    (local (ok parsed) (pcall spec.parse value))
    (if ok
        (set value parsed)
        (set err parsed)))
  (when (and (not err) spec.choices)
    (var matched false)
    (each [_ choice (ipairs spec.choices)]
      (when (= choice value)
        (set matched true)))
    (when (not matched)
      (set err (.. "invalid value for " spec.key))))
  (if err
      {:ok false :error err}
      {:ok true :value value}))

(fn merge-option [store opt value]
  (if opt.repeatable?
      (do
        (local existing (or (. store opt.key) []))
        (table.insert existing value)
        (set (. store opt.key) existing))
      (if opt.count?
          (set (. store opt.key) (+ (or (. store opt.key) 0) 1))
          (set (. store opt.key) value))))

(fn normalize-option [opt]
  (local key (normalize-key opt.key))
  {:key key
   :short opt.short
   :long opt.long
   :help opt.help
   :hint opt.hint
   :default opt.default
   :required? opt.required?
   :repeatable? opt.repeatable?
   :count? opt.count?
   :takes-value? (or opt.takes-value? opt.value?)
   :metavar opt.metavar
   :type opt.type
   :choices opt.choices
   :parse opt.parse
   :is-help? opt.is-help?
   :is-version? opt.is-version?})

(fn normalize-positional [pos]
  (local key (normalize-key pos.key))
  {:key key
   :help pos.help
   :metavar pos.metavar
   :required? pos.required?
   :repeatable? pos.repeatable?
   :default pos.default
   :type pos.type
   :choices pos.choices
   :parse pos.parse})

(fn parser [spec]
  (local options [])
  (local positionals [])
  (each [_ opt (ipairs (or spec.options []))]
    (table.insert options (normalize-option opt)))
  (each [_ pos (ipairs (or spec.positionals []))]
    (table.insert positionals (normalize-positional pos)))
  (when (not (= spec.add-help? false))
    (table.insert options {:key "help"
                           :short "h"
                           :long "help"
                           :help "Show this help message and exit"
                           :is-help? true}))
  (when spec.add-version?
    (table.insert options {:key "version"
                           :long "version"
                           :help "Show version information and exit"
                           :is-version? true}))
  (local usage (build-usage spec options positionals))
  (local long-map {})
  (local short-map {})
  (each [_ opt (ipairs options)]
    (when opt.long
      (set (. long-map opt.long) opt))
    (when opt.short
      (set (. short-map opt.short) opt)))

  (fn parse [argv]
    (local store {})
    (local rest [])
    (local unknown [])
    (local assigned [])
    (var pos-index 1)
    (var stop-options false)
    (var done nil)

    (each [_ opt (ipairs options)]
      (when (not (= opt.default nil))
        (set (. store opt.key) opt.default))
      (when opt.repeatable?
        (set (. store opt.key) []))
      (when opt.count?
        (set (. store opt.key) 0)))
    (each [_ pos (ipairs positionals)]
      (when (not (= pos.default nil))
        (set (. store pos.key) pos.default)))

    (fn finish [result]
      (set done result))

    (fn fail [msg]
      (finish {:ok false :error msg :usage usage}))

    (fn finish-help []
      (finish {:ok false :help? true :usage usage}))

    (fn finish-version []
      (finish {:ok false :version? true :usage usage}))

    (fn assign-positional [token]
      (local pos (. positionals pos-index))
      (if (not pos)
          (table.insert rest token)
          (do
            (local parsed (parse-value pos token))
            (when (not parsed.ok)
              (fail parsed.error))
            (when (not done)
              (if pos.repeatable?
                  (do
                    (local list (or (. store pos.key) []))
                    (table.insert list parsed.value)
                    (set (. store pos.key) list))
                  (do
                    (set (. store pos.key) parsed.value)
                    (table.insert assigned parsed.value)
                    (set pos-index (+ pos-index 1))))))))

    (local args [])
    (when argv
      (var idx 1)
      (while (<= idx (length argv))
        (table.insert args (. argv idx))
        (set idx (+ idx 1))))

    (var i 1)
    (fn next-arg []
      (set i (+ i 1))
      (. args i))

    (fn apply-value [opt value]
      (local parsed (parse-value opt value))
      (when (not parsed.ok)
        (fail parsed.error))
      (when (not done)
        (merge-option store opt parsed.value)))

    (fn handle-long [token]
      (local eq-idx (string.find token "=" 3 true))
      (local name (if eq-idx
                      (string.sub token 3 (- eq-idx 1))
                      (string.sub token 3)))
      (local opt (. long-map name))
      (if (not opt)
          (if spec.allow-unknown?
              (table.insert unknown token)
              (fail (.. "unknown option: " token)))
          (do
            (when opt.is-help? (finish-help))
            (when opt.is-version? (finish-version))
            (when (not done)
              (if opt.takes-value?
                  (do
                    (local value (if eq-idx
                                     (string.sub token (+ eq-idx 1))
                                     (next-arg)))
                    (if (= value nil)
                        (fail (.. "missing value for --" name))
                        (apply-value opt value)))
                  (if eq-idx
                      (do
                        (local parsed (parse-bool (string.sub token (+ eq-idx 1))))
                        (if parsed.ok
                            (merge-option store opt parsed.value)
                            (fail parsed.error)))
                      (merge-option store opt true)))))))

    (fn handle-short [token]
      (var consumed false)
      (var j 2)
      (while (and (<= j (string.len token)) (not consumed) (not done))
        (local ch (string.sub token j j))
        (local opt (. short-map ch))
        (if (not opt)
            (if spec.allow-unknown?
                (table.insert unknown (.. "-" ch))
                (fail (.. "unknown option: -" ch)))
            (do
              (when opt.is-help? (finish-help))
              (when opt.is-version? (finish-version))
              (when (not done)
                (if opt.takes-value?
                    (do
                      (local remainder (if (< j (string.len token))
                                           (string.sub token (+ j 1))
                                           nil))
                      (local value (if remainder remainder (next-arg)))
                      (if (= value nil)
                          (fail (.. "missing value for -" ch))
                          (apply-value opt value))
                      (set consumed true))
                    (merge-option store opt true)))))
        (set j (+ j 1))))

    (while (and (<= i (length args)) (not done))
      (local token (. args i))
      (if stop-options
          (assign-positional token)
          (if (= token "--")
              (set stop-options true)
              (if (and (> (string.len token) 2) (= (string.sub token 1 2) "--"))
                  (handle-long token)
                  (if (and (> (string.len token) 1) (= (string.sub token 1 1) "-"))
                      (handle-short token)
                      (assign-positional token)))))
      (set i (+ i 1)))

    (if done
        done
        (do
          (each [_ opt (ipairs options)]
            (when (and opt.required? (= (. store opt.key) nil))
              (set done {:ok false :error (.. "missing required option: " opt.key) :usage usage})))
          (each [_ pos (ipairs positionals)]
            (when (and pos.required? (= (. store pos.key) nil))
              (set done {:ok false :error (.. "missing required argument: " (or pos.metavar pos.key)) :usage usage})))
          (if done
              done
              {:ok true :values store :positionals assigned :rest rest :unknown unknown :usage usage}))))

  {:parse parse :usage usage :options options :positionals positionals})

(fn parse [spec argv]
  (local inst (parser spec))
  (inst.parse argv))

{:parser parser
 :parse parse
 :build-usage build-usage}
