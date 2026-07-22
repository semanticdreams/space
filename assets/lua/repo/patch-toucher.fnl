(fn unescape-quoted-path [s]
  (var pos 1)
  (var buf [])
  (while (<= pos (# s))
    (local c (string.sub s pos pos))
    (if (= c "\\")
        (do
          (local next-c (string.sub s (+ pos 1) (+ pos 1)))
          (if (= next-c "\\")
              (do
                (table.insert buf "\\")
                (set pos (+ pos 2)))
              (= next-c "\"")
              (do
                (table.insert buf "\"")
                (set pos (+ pos 2)))
              (= next-c "t")
              (do
                (table.insert buf "\t")
                (set pos (+ pos 2)))
              (= next-c "n")
              (do
                (table.insert buf "\n")
                (set pos (+ pos 2)))
              (= next-c "r")
              (do
                (table.insert buf "\r")
                (set pos (+ pos 2)))
              (string.match next-c "[0-7]")
              (do
                (var octal-digits next-c)
                (for [i 1 2]
                  (when (= (# octal-digits) i)
                    (local oct-char (string.sub s (+ pos i 1) (+ pos i 1)))
                    (when (and oct-char (string.match oct-char "[0-7]"))
                      (set octal-digits (.. octal-digits oct-char)))))
                (local byte-val (tonumber octal-digits 8))
                (table.insert buf (string.char byte-val))
                (set pos (+ pos 1 (# octal-digits))))
              (error (.. "unsupported quotePath escape: \\" next-c))))
        (do
          (table.insert buf c)
          (set pos (+ pos 1)))))
  (table.concat buf))

(fn normalize-patch-path [p]
  (var path p)
  (when path
    (when (and (>= (# path) 2) (or (= (string.sub path 1 2) "a/") (= (string.sub path 1 2) "b/")))
      (set path (string.sub path 3)))
    (when (and (>= (# path) 2) (= (string.sub path 1 2) "./"))
      (set path (string.sub path 3)))
    (set path (unescape-quoted-path path)))
  path)

(fn has-symlink-modes [patch-text]
  (var in-header? false)
  (var found false)
  (each [line (string.gmatch patch-text "([^\n]*)")]
    (when (string.match line "^diff %-%-git ")
      (set in-header? true))
    (when (string.match line "^%-%-%- ")
      (set in-header? false))
    (when in-header?
      (local cleaned (string.gsub line "\r$" ""))
      (when (or (= cleaned "new file mode 120000")
                (= cleaned "new mode 120000")
                (= cleaned "old mode 120000"))
        (set found true))))
  found)

(fn extract-header-path [line]
  (var result nil)
  (each [_ marker-re (ipairs ["%-%-%-" "%+%+%+"])]
    (each [_ prefix (ipairs ["a" "b"])]
      (when (not result)
        (local bare (string.match line (.. "^" marker-re "%s+" prefix "/([^\t]+)")))
        (when (and bare (not= bare "/dev/null"))
          (set result bare)))
      (when (not result)
        (local marker (if (= marker-re "%-%-%-") "---" "+++"))
        (local header (.. marker " \"" prefix "/"))
        (when (= (string.sub line 1 (# header)) header)
          (var pos (+ (# header) 1))
          (var buf [])
          (var found false)
          (while (and (not found) (<= pos (# line)))
            (local c (string.sub line pos pos))
             (if (= c "\\")
                 (do
                   (local next-c (string.sub line (+ pos 1) (+ pos 1)))
                   (if (or (= next-c "\"") (= next-c "\\"))
                       (do
                         (table.insert buf "\\")
                         (table.insert buf next-c)
                         (set pos (+ pos 2)))
                       (do
                         (table.insert buf c)
                         (set pos (+ pos 1)))))
                 (or (= c "\"") (= c "\t"))
                 (do
                   (set result (table.concat buf))
                   (set found true))
                 (do
                   (table.insert buf c)
                   (set pos (+ pos 1)))))
          (when (and found (= result "/dev/null"))
            (set result nil))))))
  result)

(fn touched-files [patch-text]
  (local seen {})
  (each [line (string.gmatch patch-text "([^\n]*)")]
    (local cleaned (string.gsub line "\r$" ""))
    (local matched (extract-header-path cleaned))
    (when matched
      (local np (normalize-patch-path matched))
      (when (and np (> (# np) 0) (not (. seen np)))
        (tset seen np true))))
  (local result [])
  (each [path _ (pairs seen)]
    (table.insert result path))
  (table.sort result)
  result)

{:has-symlink-modes has-symlink-modes
 :touched-files touched-files}
