(local CoreUtils (require :graph/core/utils))
(local Utils {})

(fn Utils.truncate-with-ellipsis [text max-length]
    (var content (or text ""))
    (local limit (or max-length 0))
    (if (<= limit 0)
        content
        (do
            (local len (utf8.len content))
            (when (and len (> len limit))
                (local ellipsis "...")
                (local trimmed (math.max 0 (- limit (utf8.len ellipsis))))
                (local next-index (utf8.offset content (+ trimmed 1)))
                (set content
                     (.. (string.sub content 1 (- (or next-index (string.len content)) 1))
                         ellipsis)))
            content)))

(fn Utils.wrap-text [text line-length]
    (if (or (not text) (not line-length) (<= line-length 0))
        text
        (do
            (local lines [])
            (var current "")
            (fn flush-current []
                (when (> (string.len current) 0)
                    (table.insert lines current)
                    (set current "")))
            (each [word (string.gmatch text "%S+")]
                (local word-length (or (utf8.len word) (string.len word)))
                (local current-length (or (utf8.len current) 0))
                (local separator (if (= current "") "" " "))
                (local total (+ current-length word-length (if (= separator "") 0 1)))
                (if (> total line-length)
                    (do
                        (flush-current)
                        (set current word))
                    (set current (.. current separator word))))
            (flush-current)
            (table.concat lines "\n"))))

(set Utils.ensure-glm-vec3 CoreUtils.ensure-glm-vec3)
(set Utils.ensure-glm-vec4 CoreUtils.ensure-glm-vec4)

Utils
