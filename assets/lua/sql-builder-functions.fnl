(fn install [opts]
  (local function-methods opts.function-methods)
  (local call opts.call)
  (local call-distinct opts.call-distinct)
  (local call-no-parens opts.call-no-parens)
  (local call-with-special opts.call-with-special)
  (local wrap-expr opts.wrap-expr)
  (local literal opts.literal)

  (local Functions
    (setmetatable
      {}
      {:__index (fn [_ key]
                  (fn [...]
                    (local name (string.upper (tostring key)))
                    (call name ...)))}))

  (local FunctionNames
    ["count" "sum" "avg" "min" "max" "std" "stddev" "abs" "first" "last"
     "sqrt" "floor" "approximate_percentile" "cast" "convert" "to_char" "signed" "unsigned"
     "date" "datediff" "timediff" "date_add" "to_date" "timestamp" "timestampadd"
     "ascii" "nullif" "bin" "concat" "insert" "length" "upper" "lower" "substring"
     "reverse" "trim" "split_part" "regexp_matches" "regexp_like" "replace"
     "now" "utc_timestamp" "current_timestamp" "current_date" "current_time"
     "extract" "isnull" "coalesce" "ifnull" "nvl"])

  (local Analytics
    {})

  (set Analytics.rank (fn [] (call "RANK")))
  (set Analytics.dense_rank (fn [] (call "DENSE_RANK")))
  (set Analytics.row_number (fn [] (call "ROW_NUMBER")))
  (set Analytics.ntile (fn [term] (call "NTILE" term)))
  (set Analytics.first_value (fn [...] (call "FIRST_VALUE" ...)))
  (set Analytics.last_value (fn [...] (call "LAST_VALUE" ...)))
  (set Analytics.median (fn [term] (call "MEDIAN" term)))
  (set Analytics.avg (fn [term] (call "AVG" term)))
  (set Analytics.stddev (fn [term] (call "STDDEV" term)))
  (set Analytics.stddev_pop (fn [term] (call "STDDEV_POP" term)))
  (set Analytics.stddev_samp (fn [term] (call "STDDEV_SAMP" term)))
  (set Analytics.variance (fn [term] (call "VARIANCE" term)))
  (set Analytics.var_pop (fn [term] (call "VAR_POP" term)))
  (set Analytics.var_samp (fn [term] (call "VAR_SAMP" term)))
  (set Analytics.count (fn [term] (call "COUNT" term)))
  (set Analytics.sum (fn [term] (call "SUM" term)))
  (set Analytics.max (fn [term] (call "MAX" term)))
  (set Analytics.min (fn [term] (call "MIN" term)))
  (set Analytics.lag (fn [...] (call "LAG" ...)))
  (set Analytics.lead (fn [...] (call "LEAD" ...)))

  (fn build-function-helper [name ...]
    (local args [...])
    (local upper (string.upper name))
    (if (= name "current_timestamp")
        (call-no-parens "CURRENT_TIMESTAMP")
        (= name "extract")
        (do
          (assert (= (# args) 2) "extract expects (date_part field)")
          (setmetatable
            {:__tag :call
             :_extract true
             :_extract_part (wrap-expr (. args 1))
             :_extract_field (wrap-expr (. args 2))}
            {:__index function-methods}))
        (= name "cast")
        (do
          (assert (= (# args) 2) "cast expects (term as_type)")
          (call-with-special upper [(. args 1)] {:kind :as-type :value (. args 2)}))
        (= name "convert")
        (do
          (assert (= (# args) 2) "convert expects (term encoding)")
          (call-with-special upper [(. args 1)] {:kind :using :value (. args 2)}))
        (= name "approximate_percentile")
        (do
          (assert (= (# args) 2) "approximate_percentile expects (term percentile)")
          (call-with-special upper
                             [(. args 1)]
                             {:kind :raw
                              :value (.. "USING PARAMETERS percentile="
                                         (tostring (. args 2)))}))
        (or (= name "date_add") (= name "timestampadd"))
        (do
          (assert (= (# args) 3) (.. name " expects (date_part interval term)"))
          (call upper (literal (. args 1)) (. args 2) (. args 3)))
        (call upper ...)))

  (fn install-function-helpers! [target]
    (each [_ name (ipairs FunctionNames)]
      (set (. target name)
           (fn [...]
             (build-function-helper name ...))))
    target)

  (install-function-helpers! Functions)

  (set function-methods.count (fn [value] (call "COUNT" value)))
  (set function-methods.count-distinct (fn [value] (call-distinct "COUNT" value)))
  (set function-methods.count_distinct (fn [value] (call-distinct "COUNT" value)))
  (set function-methods.sum (fn [value] (call "SUM" value)))
  (set function-methods.avg (fn [value] (call "AVG" value)))
  (set function-methods.min (fn [value] (call "MIN" value)))
  (set function-methods.max (fn [value] (call "MAX" value)))

  {:Functions Functions
   :Analytics Analytics})

{:install install}
