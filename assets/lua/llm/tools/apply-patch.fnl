(local fs (require :fs))

(local tool-name "apply_patch")

(fn require-fs []
    (assert (and fs fs.read-file fs.write-file fs.stat) "apply_patch tool requires fs bindings read-file, write-file, and stat")
    fs)

(fn normalize-newlines [text]
    (local without-crlf (string.gsub text "\r\n" "\n"))
    (select 1 (string.gsub without-crlf "\r" "\n")))

(fn split-lines [text]
    (if (= text "")
        (values [] false)
        (do
            (local lines [])
            (each [line (string.gmatch text "([^\n]*)\n")]
                (table.insert lines line))
            (local len (string.len text))
            (local ends-with-newline (and (> len 0) (= (string.sub text len len) "\n")))
            (if (not ends-with-newline)
                (table.insert lines (or (string.match text "([^\n]*)$") "")))
            (values lines ends-with-newline))))

(fn join-lines [lines ends-with-newline]
    (local combined (table.concat lines "\n"))
    (if ends-with-newline
        (.. combined "\n")
        combined))

(fn normalize-patch-path [path]
    (when path
        (local trimmed (string.gsub path "^%s*(.-)%s*$" "%1"))
        (local without-prefix (if (and (>= (string.len trimmed) 2)
                                       (or (= (string.sub trimmed 1 2) "a/")
                                           (= (string.sub trimmed 1 2) "b/")))
                                 (string.sub trimmed 3)
                                 trimmed))
        (if (and (>= (string.len without-prefix) 2)
                 (= (string.sub without-prefix 1 2) "./"))
            (string.sub without-prefix 3)
            without-prefix)))

(fn parse-hunk-header [line line-number]
    (local (a-start a-count b-start b-count) (string.match line "^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@"))
    (assert a-start (.. "Invalid hunk header at line " line-number ": " line))
    {:header line
     :a-start (tonumber a-start)
     :a-count (if (> (string.len a-count) 0) (tonumber a-count) 1)
     :b-start (tonumber b-start)
     :b-count (if (> (string.len b-count) 0) (tonumber b-count) 1)
     :lines []})

(fn finalize-hunk [hunk]
    (local context [])
    (var original-count 0)
    (var new-count 0)
    (each [_ line (ipairs hunk.lines)]
        (local prefix (string.sub line 1 1))
        (local text (string.sub line 2))
        (when (or (= prefix " ") (= prefix "-"))
            (table.insert context text)
            (set original-count (+ original-count 1)))
        (when (or (= prefix " ") (= prefix "+"))
            (set new-count (+ new-count 1))))
    (assert (= original-count hunk.a-count)
            (.. "Hunk original line count mismatch; expected " hunk.a-count " got " original-count))
    (assert (= new-count hunk.b-count)
            (.. "Hunk new line count mismatch; expected " hunk.b-count " got " new-count))
    (set hunk.context context)
    hunk)

(fn parse-patch [patch path]
    (local normalized (normalize-newlines patch))
    (local (lines trailing-newline) (split-lines normalized))
    (var hunks [])
    (var current nil)
    (var patch-path nil)
    (var new-trailing nil)

    (fn flush []
        (when current
            (table.insert hunks (finalize-hunk current))
            (set current nil)))

    (each [idx line (ipairs lines)]
        (local update (string.match line "^%*%*%*%s+Update File:%s*(.+)$"))
        (local add (string.match line "^%*%*%*%s+Add File:%s*(.+)$"))
        (local del (string.match line "^%*%*%*%s+Delete File:%s*(.+)$"))
        (local minus (string.match line "^%-%-%-%s*(.+)"))
        (local plus (string.match line "^%+%+%+%s*(.+)"))
        (if (string.match line "^%*%*%*%s+Begin Patch") nil
            (string.match line "^%*%*%*%s+End Patch") (flush)
            update (set patch-path (normalize-patch-path update))
            add (set patch-path (normalize-patch-path add))
            del (set patch-path (normalize-patch-path del))
            minus (when (not (= minus "/dev/null"))
                        (set patch-path (normalize-patch-path minus)))
            plus (when (not (= plus "/dev/null"))
                       (set patch-path (normalize-patch-path plus)))
            (string.match line "^diff%s") nil
            (string.match line "^@@") (do (flush)
                                          (set current (parse-hunk-header line idx)))
            current (if (string.match line "^\\ No newline at end of file")
                          (when (> (# current.lines) 0)
                              (local last-line (. current.lines (# current.lines)))
                              (local last-prefix (string.sub last-line 1 1))
                              (when (= last-prefix "+")
                                  (set new-trailing false)))
                          (do
                              (local prefix (string.sub line 1 1))
                              (assert (or (= prefix " ") (= prefix "+") (= prefix "-"))
                                      (.. "Invalid hunk line at " idx ": " line))
                              (table.insert current.lines line)))
            true nil))

    (flush)
    (assert (> (# hunks) 0) "apply_patch found no hunks in patch")

    (when (and patch-path (not (= patch-path "/dev/null")))
        (local normalized-path (normalize-patch-path path))
        (assert (= patch-path normalized-path)
                (.. "Patch targets " patch-path " but path argument is " normalized-path)))

    {:hunks hunks
     :trailing trailing-newline
     :new-trailing new-trailing})

(fn match-context-at? [lines context start-index]
    (local ctx-length (# context))
    (var index start-index)
    (when (< index 1) (set index 1))
    (if (> (+ index ctx-length -1) (# lines))
        false
        (do
            (var i 1)
            (var matches true)
            (while (and matches (<= i ctx-length))
                (when (not (= (. lines (+ index i -1)) (. context i)))
                    (set matches false))
                (set i (+ i 1)))
            matches)))

(fn find-position [lines context start-hint]
    (local ctx-length (# context))
    (local total (# lines))
    (if (= ctx-length 0)
        (do
            (local clamped (math.max 1 (math.min start-hint (+ total 1))))
            clamped)
        (do
            (local max-start (math.max 1 (+ (- total ctx-length) 1)))
            (local hint (math.max 1 (math.min start-hint max-start)))
            (if (match-context-at? lines context hint)
                hint
                (do
                    (var idx 1)
                    (var found nil)
                    (while (and (not found) (<= idx max-start))
                        (when (match-context-at? lines context idx)
                            (set found idx))
                        (set idx (+ idx 1)))
                    found)))))

(fn apply-hunk [lines hunk start-index]
    (assert start-index (.. "Unable to locate context for hunk: " hunk.header))
    (local output [])
    (var cursor 1)
    (while (< cursor start-index)
        (table.insert output (. lines cursor))
        (set cursor (+ cursor 1)))

    (each [_ line (ipairs hunk.lines)]
        (local prefix (string.sub line 1 1))
        (local text (string.sub line 2))
        (if (= prefix " ")
            (do
                (assert (= (. lines cursor) text)
                        (.. "Context mismatch near hunk " hunk.header))
                (table.insert output text)
                (set cursor (+ cursor 1)))
            (= prefix "-")
            (do
                (assert (= (. lines cursor) text)
                        (.. "Delete mismatch near hunk " hunk.header))
                (set cursor (+ cursor 1)))
            (= prefix "+")
            (table.insert output text)
            (error (.. "Invalid hunk line prefix: " prefix))))

    (while (<= cursor (# lines))
        (table.insert output (. lines cursor))
        (set cursor (+ cursor 1)))

    output)

(fn resolve-path [path ctx]
  (local cwd (or (and ctx ctx.cwd) (fs.cwd)))
  (if (= (string.sub path 1 1) "/")
      path
      (fs.join-path cwd path)))

(fn apply-patch [args _ctx]
    (local options (or args {}))
    (local path options.path)
    (local patch options.patch)
    (assert path "apply_patch requires path")
    (assert (= (type path) :string) "apply_patch.path must be a string")
    (assert patch "apply_patch requires patch")
    (assert (= (type patch) :string) "apply_patch.patch must be a string")
    (local allow-create (if (not (= options.allow_create nil)) options.allow_create true))
    (assert (or (= allow-create true) (= allow-create false)) "apply_patch.allow_create must be a boolean")

    (local binding (require-fs))
    (local target (resolve-path path _ctx))
    (local exists (binding.exists target))
    (when (and (not exists) (not allow-create))
        (error (.. "apply_patch path does not exist: " target)))

    (when exists
        (local info (binding.stat target))
        (when info.is-dir
            (error (.. "apply_patch cannot modify a directory: " target))))

    (local original (if exists (binding.read-file target) ""))
    (local (original-lines trailing-newline) (split-lines (normalize-newlines original)))
    (local parsed (parse-patch patch path))
    (local hunks parsed.hunks)

    (var working original-lines)
    (var offset 0)
    (each [_ hunk (ipairs hunks)]
        (local start-hint (+ hunk.a-start offset))
        (local position (find-position working hunk.context start-hint))
        (set working (apply-hunk working hunk position))
        (set offset (+ offset (- hunk.a-count) hunk.b-count)))

    (local default-trailing (if exists trailing-newline true))
    (local ends-with-newline (if (not (= parsed.new-trailing nil)) parsed.new-trailing default-trailing))
    (local content (join-lines working ends-with-newline))
    (local (ok err) (pcall binding.write-file target content))
    (if (not ok)
        (error (.. "apply_patch failed to write " path ": " err)))

    {:tool tool-name
     :path path
     :bytes (string.len content)
     :hunks_applied (# hunks)})

{:name tool-name
 :description (.. "Apply a unified diff patch to a file with context matching and optional creation. "
                  "Example:\n"
                  "*** Begin Patch\n"
                  "*** Update File: path/to/file.txt\n"
                  "@@ -1,1 +1,1 @@\n"
                  "-old line\n"
                  "+new line\n"
                  "*** End Patch")
 :parameters {:type "object"
              :properties {:path {:type "string"
                                  :description "Target file path to patch"}
                           :patch {:type "string"
                                   :description "Unified diff patch text targeting the file"}
                           :allow_create {:type "boolean"
                                          :description "Whether to create the file if it does not exist"
                                          :default true}}
              :required ["path" "patch" "allow_create"]
              :additionalProperties false}
 :strict true
 :call apply-patch}
