(local tests [])
(local fs (require :fs))
(local xapian (require :xapian))

(var temp-counter 0)
(local xapian-temp-root (fs.join-path "/tmp/space/tests" "xapian-test-tmp"))

(fn make-temp-dir []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path xapian-temp-root (.. "xapian-test-" (os.time) "-" temp-counter)))

(fn with-temp-dir [f]
  (local dir (make-temp-dir))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

(fn contains? [items needle]
  (var found false)
  (each [_ item (ipairs items)]
    (when (= item needle)
      (set found true)))
  found)

(fn collect-docids [matches]
  (local ids [])
  (each [_ entry (ipairs matches)]
    (table.insert ids entry.docid))
  ids)

(fn xapian-basic-index-search []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:data "first doc" :terms ["hello" "world"] :values {0 "alpha"}}))
    (local doc2 (xapian.document {:data "second doc" :terms ["hello" "mars"] :values {0 "beta"}}))
    (local id1 (db:add-document doc1))
    (local id2 (db:add-document doc2))
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local result (rdb:search "hello" {:limit 10}))
    (assert (= result.count 2))
    (assert (>= result.estimated 2))
    (local matches result.matches)
    (assert (= (# matches) 2))
    (local ids (collect-docids matches))
    (assert (contains? ids id1) "missing doc1 in results")
    (assert (contains? ids id2) "missing doc2 in results")

    (local doc (rdb:get-document id1))
    (assert (= doc.data "first doc"))
    (assert (= (. doc.values 0) "alpha"))
    (rdb:close))))

(fn xapian-replace-delete []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:data "alpha" :terms ["alpha"]}))
    (local id1 (db:add-document doc1))
    (db:commit)

    (local doc2 (xapian.document {:data "beta" :terms ["beta"]}))
    (db:replace-document id1 doc2)
    (db:commit)

    (local replaced (db:search "beta" {:limit 5}))
    (assert (= replaced.count 1))

    (db:delete-document id1)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local alpha (rdb:search "alpha" {:limit 5}))
    (local beta (rdb:search "beta" {:limit 5}))
    (assert (= alpha.count 0))
    (assert (= beta.count 0))
    (rdb:close))))

(fn xapian-query-flags []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "hello world"}))
    (local doc2 (xapian.document {:text "mars world"}))
    (db:add-document doc1)
    (db:add-document doc2)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local upper (rdb:search "hello OR mars" {:flags ["boolean"]}))
    (assert (= upper.count 2))

    (local lower (rdb:search "hello or mars" {:flags ["boolean"]}))
    (assert (= lower.count 0))

    (local lower-ok (rdb:search "hello or mars" {:flags ["boolean" "boolean-any-case"]}))
    (assert (= lower-ok.count 2))
    (rdb:close))))

(fn xapian-prefixes-and-filters []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "hello world"}))
    (local doc2 (xapian.document {:text "hello world"}))
    (doc1:add-term "Thello")
    (doc2:add-term "Tmars")
    (doc1:add-term "Xcat")
    (doc2:add-term "Xdog")
    (db:add-document doc1)
    (db:add-document doc2)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local pref (rdb:search "title:hello"
      {:prefixes [{:field "title" :prefix "T"}]}))
    (assert (= pref.count 1))

    (local bool-pref (rdb:search "type:cat"
      {:boolean-prefixes [{:field "type" :prefix "X"}]}))
    (assert (= bool-pref.count 1))

    (local filtered (rdb:search "hello"
      {:boolean-filters [{:prefix "X" :value "cat"}]}))
    (assert (= filtered.count 1))
    (rdb:close))))

(fn xapian-sorting-and-ranges []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc-a (xapian.document {:text "hello"}))
    (local doc-b (xapian.document {:text "hello"}))
    (local doc-c (xapian.document {:text "hello"}))
    (doc-a:add-value 0 "a")
    (doc-b:add-value 0 "b")
    (doc-c:add-value 0 "c")
    (db:add-document doc-a)
    (db:add-document doc-b)
    (db:add-document doc-c)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local asc (rdb:search "hello" {:sort {:value 0}}))
    (local first-asc (. asc.matches 1))
    (assert (= (. first-asc.values 0) "a"))
    (local desc (rdb:search "hello" {:sort {:value 0 :descending true}}))
    (local first-desc (. desc.matches 1))
    (assert (= (. first-desc.values 0) "c"))

    (local range (rdb:search "hello" {:value-ranges [{:slot 0 :start "b" :end "c"}]}))
    (assert (= range.count 2))
    (rdb:close))))

(fn xapian-collapse []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc-1 (xapian.document {:text "hello"}))
    (local doc-2 (xapian.document {:text "hello"}))
    (local doc-3 (xapian.document {:text "hello"}))
    (doc-1:add-value 1 "group-1")
    (doc-2:add-value 1 "group-1")
    (doc-3:add-value 1 "group-2")
    (db:add-document doc-1)
    (db:add-document doc-2)
    (db:add-document doc-3)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local collapsed (rdb:search "hello" {:collapse {:value 1 :max 1}}))
    (assert (= collapsed.count 2))
    (rdb:close))))

(fn xapian-spelling []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (db:add-spelling "hello" 5)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local suggestion (rdb:spelling-suggestion "helo" 2))
    (assert (= suggestion "hello"))

    (local result (rdb:search "helo" {:flags ["spelling-correction"] :include-corrected true}))
    (assert (= result.corrected "hello"))
    (rdb:close))))

(fn xapian-synonyms []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc (xapian.document {:text "auto"}))
    (db:add-document doc)
    (db:add-synonym "car" "auto")
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local syns (rdb:synonyms "car"))
    (assert (= (. syns 1) "auto"))
    (local result (rdb:search "car" {:flags ["auto-synonyms"]}))
    (assert (= result.count 1))
    (rdb:close))))

(fn xapian-expand []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc (xapian.document {:text "alpha beta"}))
    (local id (db:add-document doc))
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local base (rdb:search "alpha" {:limit 5}))
    (local expand (rdb:search "alpha"
      {:expand {:docids [id] :limit 5 :flags ["include-query-terms"]}}))
    (assert (>= base.count 1))
    (assert expand.expanded)
    (assert (>= expand.expanded.count 1))
    (rdb:close))))

(fn xapian-termlist-and-positions []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc (xapian.document {:text "alpha beta alpha"}))
    (local id (db:add-document doc))
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local terms (rdb:termlist id {:positions true}))
    (local term-names [])
    (each [_ entry (ipairs terms)]
      (table.insert term-names entry.term))
    (assert (contains? term-names "alpha"))
    (assert (contains? term-names "beta"))

    (local alpha-positions (rdb:positions id "alpha"))
    (assert (= (# alpha-positions) 2))
    (local tf (rdb:termfreq "alpha"))
    (assert (>= tf 1))
    (rdb:close))))

(fn xapian-weighting-and-rset []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "alpha beta"}))
    (local doc2 (xapian.document {:text "alpha gamma"}))
    (local id1 (db:add-document doc1))
    (db:add-document doc2)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local result (rdb:search "alpha"
      {:weighting {:name "bm25" :params {:k1 1.2 :b 0.75}}
       :rset [id1]}))
    (assert (>= result.count 1))

    (local bool-result (rdb:search "alpha" {:weighting "bool"}))
    (assert (>= bool-result.count 1))
    (rdb:close))))

(fn xapian-range-and-stoplist []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "the running fox"}))
    (local doc2 (xapian.document {:text "jumping fox"}))
    (doc1:add-value 2 "20200101")
    (doc2:add-value 2 "20210101")
    (doc1:add-value 3 (xapian.sortable-serialise 10))
    (doc2:add-value 3 (xapian.sortable-serialise 20))
    (db:add-document doc1)
    (db:add-document doc2)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local result (rdb:search "date:2020-01-01..2020-12-31"
      {:ranges [{:type "date" :slot 2 :prefix "date:"}]
       :include-stoplist true
       :include-unstem true
       :stemmer "en"}))
    (assert (= result.count 1))
    (assert result.stoplist)
    (assert result.unstem)

    (local numeric (rdb:search "price:5..15"
      {:ranges [{:type "number" :slot 3 :prefix "price:"}]}))
    (assert (= numeric.count 1))
    (rdb:close))))

(fn xapian-postings []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "alpha beta"}))
    (local doc2 (xapian.document {:text "alpha alpha"}))
    (local id1 (db:add-document doc1))
    (local id2 (db:add-document doc2))
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local postings (rdb:postings "alpha" {:positions true}))
    (assert (>= (# postings) 2))
    (local first-entry (. postings 1))
    (local second-entry (. postings 2))
    (local first (if (= first-entry.docid id1)
                     first-entry
                     second-entry))
    (assert (>= first.wdf 1))
    (assert first.positions)
    (local second (if (= first-entry.docid id2)
                      first-entry
                      second-entry))
    (assert (>= second.wdf 2))
    (rdb:close))))

(fn xapian-stats []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "alpha beta"}))
    (local doc2 (xapian.document {:text "alpha gamma"}))
    (local id1 (db:add-document doc1))
    (db:add-document doc2)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local stats (rdb:stats))
    (assert (= stats.doccount 2))
    (assert (>= stats.avg-length 1))
    (assert (>= stats.total-length 1))

    (local docstats (rdb:doc-stats id1))
    (assert (>= docstats.doclength 1))
    (assert (>= docstats.unique-terms 1))

    (local cf (rdb:collection-freq "alpha"))
    (assert (>= cf 2))
    (rdb:close))))

(fn xapian-metadata []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (db:set-metadata "app.version" "1.0.0")
    (db:set-metadata "app.owner" "qa")
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (assert (= (rdb:get-metadata "app.version") "1.0.0"))
    (local keys (rdb:metadata-keys "app."))
    (assert (>= (# keys) 2))
    (rdb:close))))

(fn xapian-mset-extras []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "alpha beta"}))
    (local doc2 (xapian.document {:text "alpha beta"}))
    (doc1:add-value 1 "group-1")
    (doc2:add-value 1 "group-1")
    (doc1:add-value 0 "a")
    (doc2:add-value 0 "b")
    (db:add-document doc1)
    (db:add-document doc2)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local result (rdb:search "alpha beta"
      {:collapse {:value 1 :max 1}
       :sort {:value 0}
       :include-collapse true
       :include-sort-key true
       :include-matching-terms true}))
    (assert (= result.count 1))
    (local item (. result.matches 1))
    (assert item.collapse-key)
    (assert item.sort-key)
    (assert item.matching-terms)
    (assert (>= (# item.matching-terms) 1))
    (rdb:close))))

(fn xapian-spellings-and-synonym-keys []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (db:add-spelling "hello" 3)
    (db:add-synonym "car" "auto")
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local spellings (rdb:spellings))
    (assert (>= (# spellings) 1))
    (local keys (rdb:synonym-keys))
    (assert (>= (# keys) 1))
    (rdb:close))))

(fn xapian-values []
  (with-temp-dir (fn [root]
    (local db (xapian.open root {:writable true :create true :overwrite true}))
    (local doc1 (xapian.document {:text "alpha"}))
    (local doc2 (xapian.document {:text "beta"}))
    (doc1:add-value 4 "v1")
    (doc2:add-value 4 "v2")
    (db:add-document doc1)
    (db:add-document doc2)
    (db:commit)
    (db:close)

    (local rdb (xapian.open root))
    (local value-items (rdb:values 4))
    (assert (>= (# value-items) 2))
    (local first (. value-items 1))
    (assert first.docid)
    (assert first.value)
    (rdb:close))))

(table.insert tests {:name "xapian basic index + search" :fn xapian-basic-index-search})
(table.insert tests {:name "xapian replace and delete" :fn xapian-replace-delete})
(table.insert tests {:name "xapian query flags" :fn xapian-query-flags})
(table.insert tests {:name "xapian prefixes and boolean filters" :fn xapian-prefixes-and-filters})
(table.insert tests {:name "xapian sorting and ranges" :fn xapian-sorting-and-ranges})
(table.insert tests {:name "xapian collapse" :fn xapian-collapse})
(table.insert tests {:name "xapian spelling" :fn xapian-spelling})
(table.insert tests {:name "xapian synonyms" :fn xapian-synonyms})
(table.insert tests {:name "xapian expand" :fn xapian-expand})
(table.insert tests {:name "xapian termlist and positions" :fn xapian-termlist-and-positions})
(table.insert tests {:name "xapian weighting and rset" :fn xapian-weighting-and-rset})
(table.insert tests {:name "xapian range and stoplist" :fn xapian-range-and-stoplist})
(table.insert tests {:name "xapian postings" :fn xapian-postings})
(table.insert tests {:name "xapian stats" :fn xapian-stats})
(table.insert tests {:name "xapian metadata" :fn xapian-metadata})
(table.insert tests {:name "xapian mset extras" :fn xapian-mset-extras})
(table.insert tests {:name "xapian spellings and synonym keys" :fn xapian-spellings-and-synonym-keys})
(table.insert tests {:name "xapian values" :fn xapian-values})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "xapian"
                       :tests tests})))

{:name "xapian"
 :tests tests
 :main main}
