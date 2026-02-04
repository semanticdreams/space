(fn fuzzy-match [needle haystack]
    (local query (string.lower (or needle "")))
    (local target (string.lower (or haystack "")))
    (if (= query "")
        true
        (not (not (string.find target query 1 true)))))

{:fuzzy-match fuzzy-match}
