(local Input (require :input))
(local ListView (require :list-view))
(local Button (require :button))
(local Text (require :text))
(local {: Flex : FlexChild} (require :flex))
(local Signal (require :signal))
(local Ripgrep (require :ripgrep))
(local ExternalEditor (require :external-editor))

(local default-max-results 200)
(local default-max-count-per-file 20)
(local default-max-filesize "512K")
(local default-max-label-chars 180)

(fn as-string [value fallback]
  (if (= (type value) :string)
      value
      (or fallback "")))

(fn truncate-text [text limit]
  (local value (as-string text ""))
  (if (or (not (= (type limit) :number))
          (< limit 4)
          (<= (# value) limit))
      value
      (.. (string.sub value 1 (- limit 3)) "...")))

(fn build-label [entry max-label-chars]
  (local path (or entry.path ""))
  (local line (or entry.line 0))
  (local column (or entry.column 0))
  (local text (truncate-text (or entry.text "") max-label-chars))
  (string.format "%s:%d:%d %s" path line column text))

(fn trim-results [matches max-results]
  (local source (or matches []))
  (local limit
    (if (and (= (type max-results) :number) (> max-results 0))
        max-results
        default-max-results))
  (local total (length source))
  (if (<= total limit)
      {:items source :total total :shown total :truncated false}
      (do
        (local trimmed [])
        (for [idx 1 limit]
          (table.insert trimmed (. source idx)))
        {:items trimmed :total total :shown limit :truncated true})))

(fn resolve-field [runtime options key fallback]
  (if (and runtime (not (= (. runtime key) nil)))
      (. runtime key)
      (if (and options (not (= (. options key) nil)))
          (. options key)
          fallback)))

(fn RipgrepView [opts]
  (local options (or opts {}))

  (fn build [ctx runtime-opts]
    (local runtime (or runtime-opts {}))
    (local view {:submitted (Signal)
                 :results []
                 :search-token nil
                 :last-total-results 0
                 :last-shown-results 0
                 :results-truncated false})
    (fn assert-live [action]
      (assert (not view.__dropped)
              (.. "RipgrepView " action " after drop")))

    (set view.path (as-string (resolve-field runtime options :path ".") "."))
    (set view.query (as-string (resolve-field runtime options :query "") ""))

    (local path-input
      ((Input {:text view.path
               :placeholder "Path"})
       ctx))
    (local query-input
      ((Input {:text view.query
               :placeholder "ripgrep query"})
       ctx))
    (local search-button
      ((Button {:text "Search"
                :variant :ghost
                :on-click (fn [_button _event]
                            (view:run-search))})
       ctx))
    (local status-text
      ((Text {:text "Enter a query and press Search"})
       ctx))

    (local results-list
      ((ListView {:items []
                  :name (or options.name "ripgrep-view")
                  :show-head false
                  :paginate false
                  :fill-width true
                  :scroll true
                  :builder (fn [item child-ctx]
                             (local entry (. item 1))
                             (local label (tostring (. item 2)))
                             ((Button {:text label
                                       :variant :ghost
                                       :on-click (fn [_button _event]
                                                   (view.submitted:emit entry)
                                                   (when (and entry entry.path)
                                                     (ExternalEditor.open-file entry.path (fn [] nil))))})
                              child-ctx))})
       ctx))

    (local query-row
      ((Flex {:axis 1
              :xspacing 0.3
              :xalign :stretch
              :children [(FlexChild (fn [_] query-input) 1)
                         (FlexChild (fn [_] search-button) 0)]})
       ctx))

    (local root
      ((Flex {:axis 2
              :xalign :stretch
              :yspacing 0.3
              :children [(FlexChild (fn [_] path-input) 0)
                         (FlexChild (fn [_] query-row) 0)
                         (FlexChild (fn [_] status-text) 0)
                         (FlexChild (fn [_] results-list) 1)]})
       ctx))

    (fn set-status [self text]
      (assert-live "set_status")
      (status-text:set-text (as-string text ""))
      self)

    (fn set-path [self value]
      (assert-live "set_path")
      (set self.path (as-string value ""))
      (path-input:set-text self.path)
      self)

    (fn set-query [self value]
      (assert-live "set_query")
      (set self.query (as-string value ""))
      (query-input:set-text self.query)
      self)

    (fn set-results [self matches]
      (assert-live "set_results")
      (local max-results
        (resolve-field runtime options :max-results default-max-results))
      (local max-label-chars
        (resolve-field runtime options :max-label-chars default-max-label-chars))
      (local trimmed (trim-results matches max-results))
      (set self.results trimmed.items)
      (set self.last-total-results trimmed.total)
      (set self.last-shown-results trimmed.shown)
      (set self.results-truncated trimmed.truncated)
      (local items
        (icollect [_ entry (ipairs self.results)]
          [entry (build-label entry max-label-chars)]))
      (results-list:set-items items)
      self)

    (fn cancel-search [self opts]
      (assert-live "cancel_search")
      (if (and self.search-token self.search-token.cancel)
          (self.search-token:cancel opts)
          false))

    (fn run-search [self opts]
      (assert-live "run_search")
      (local run-options (or opts {}))
      (local query (as-string (or run-options.query self.query) ""))
      (local path (as-string (or run-options.path self.path) "."))
      (set self.query query)
      (set self.path path)
      (if (= (# query) 0)
          (do
            (self:set-results [])
            (self:set-status "Query is required")
            false)
          (do
            (self:cancel-search {:suppress-callback true})
            (self:set-status "Searching...")
            (set self.search-token
                 (Ripgrep.search-async
                   {:program run-options.program
                    :program-args run-options.program-args
                    :query query
                    :paths [path]
                    :cwd run-options.cwd
                    :timeout run-options.timeout
                    :globs run-options.globs
                    :case run-options.case
                    :literal run-options.literal
                    :hidden run-options.hidden
                    :follow run-options.follow
                    :word-regexp run-options.word-regexp
                   :max-count (or run-options.max-count
                                   (resolve-field runtime options :max-count default-max-count-per-file))
                    :max-filesize (or run-options.max-filesize
                                      (resolve-field runtime options :max-filesize default-max-filesize))}
                   (fn [result]
                     (when (not self.__dropped)
                       (if result.cancelled
                           (self:set-status "Search cancelled")
                           (if result.timed-out
                               (self:set-status "Search timed out")
                               (if (not result.ok)
                                   (self:set-status
                                     (.. "Search failed"
                                         (if (> (# (or result.stderr "")) 0)
                                             (.. ": " (string.gsub result.stderr "\n$" ""))
                                             "")))
                                   (do
                                     (self:set-results result.matches)
                                     (if self.results-truncated
                                         (self:set-status
                                           (string.format "Found %d matches (showing first %d)"
                                                          self.last-total-results
                                                          self.last-shown-results))
                                         (self:set-status
                                           (string.format "Found %d matches" self.last-total-results)))))))
                       (if (and result result.matches)
                           (when (not (and result.ok (not result.cancelled) (not result.timed-out)))
                             (self:set-results result.matches))
                           (self:set-results []))))))
            true)))

    (local path-listener
      (path-input.model.changed:connect
        (fn [text]
          (set view.path (as-string text "")))))
    (local query-listener
      (query-input.model.changed:connect
        (fn [text]
          (set view.query (as-string text "")))))

    (set view.path-input path-input)
    (set view.query-input query-input)
    (set view.search-button search-button)
    (set view.status-text status-text)
    (set view.results-list results-list)
    (set view.query-row query-row)
    (set view.layout root.layout)
    (set view.set-status set-status)
    (set view.set-path set-path)
    (set view.set-query set-query)
    (set view.set-results set-results)
    (set view.cancel-search cancel-search)
    (set view.run-search run-search)
    (set view.__path-listener path-listener)
    (set view.__query-listener query-listener)

    (set view.drop
      (fn [self]
        (assert (not self.__dropped) "RipgrepView dropped twice")
        (set self.__dropped true)
        (when (and self.search-token self.search-token.cancel)
          (self.search-token:cancel {:suppress-callback true}))
        (when self.__path-listener
          (path-input.model.changed:disconnect self.__path-listener true)
          (set self.__path-listener nil))
        (when self.__query-listener
          (query-input.model.changed:disconnect self.__query-listener true)
          (set self.__query-listener nil))
        (root:drop)))

    view))

RipgrepView
