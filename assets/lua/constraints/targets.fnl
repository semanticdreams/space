;; Target resolution for Fennel constraints.
;; Resolves repo, unit, app, and explicit-file analysis targets.

(local fs (require :fs))

(local M {})

(fn assets-lua-dir []
  "Determine the absolute path to the assets/lua directory."
  (let [assets-dir (or (and _G.runtime _G.runtime.assets-path)
                       (os.getenv :SPACE_ASSETS_PATH)
                       "assets")]
    (fs.absolute (fs.join-path assets-dir "lua"))))

(fn default-suites []
  "All five constraint families active by default."
  [:scene-sandbox :lifecycle :test-isolation :layout-rendering :structure-formatting])

(fn base-name [root-path]
  "Extract a human-readable name from a directory path."
  (let [s root-path]
    ;; strip trailing slashes, take last segment
    (var name s)
    (while (or (name:match "/$") (name:match "\\$"))
      (set name (name:sub 1 (- (# name) 1))))
    (let [i (or (name:match "^.*/([^/]+)$") name)]
      i)))

(fn parse-argv [argv]
  "Parse command-line argv into a table of --flag -> [values].
  Returns {:target target-string :roots [] :files [] :error error-msg}."
  (var target nil)
  (var roots [])
  (var files [])
  (var error nil)
  (var i 1)
  (while (and (<= i (# argv)) (not error))
    (let [arg (. argv i)]
      (if (= arg "--target")
          (do
            (set i (+ i 1))
            (if (or (> i (# argv)) (= "" (. argv i))
                    (and (. argv i) (string.match (. argv i) "^%-%-")))
                (set error "missing value for --target")
                (set target (. argv i))))
          (= arg "--root")
          (do
            (set i (+ i 1))
            (if (or (> i (# argv)) (= "" (. argv i))
                    (and (. argv i) (string.match (. argv i) "^%-%-")))
                (set error "missing value for --root")
                (table.insert roots (fs.absolute (. argv i)))))
          (= arg "--file")
          (do
            (set i (+ i 1))
            (if (or (> i (# argv)) (= "" (. argv i))
                    (and (. argv i) (string.match (. argv i) "^%-%-")))
                (set error "missing value for --file")
                (table.insert files (fs.absolute (. argv i)))))
          (and (= (type arg) :string) (arg:match "^%-%-"))
          (set error (.. "unrecognized flag: " arg))
          (set error (.. "unexpected positional argument: " (tostring arg)))))
    (set i (+ i 1)))
  {:target target
   :roots roots
   :files files
   :error error})

(local supported-targets
  {:repo true
   :unit true
   :app true
   :files true})

(fn M.resolve [argv _env]
  "Parse CLI arguments into a resolved target config.
  argv: list of string arguments from the command line.
  env:  table of environment values (reserved for future use).
  Returns {:kind :repo|:unit|:app|:files
           :name string
           :roots [absolute-path-string ...]
           :files [absolute-path-string ...]
           :module-roots [absolute-path-string ...]
           :suites [:scene-sandbox :lifecycle :layout :structure]}"
  (local parsed (parse-argv (or argv [])))
  (when parsed.error
    (error parsed.error))
  (local target (. parsed :target))
  ;; Validate target
  (when (and target (not (. supported-targets target)))
    (error (.. "unsupported target: " target)))
  ;; Default to repo
  (local kind (or target :repo))
  (if (= kind :files)
      ;; Files target
      (do
        (local file-list (or parsed.files []))
        (when (= (# file-list) 0)
          (error "files target requires at least one --file"))
        {:kind :files
         :name "files"
         :roots (or parsed.roots [])
         :files file-list
         :module-roots []
         :suites (default-suites)})
      ;; repo, unit, app
      (do
        (local root-list (if (= (# parsed.roots) 0)
                           (if (= kind :repo)
                               [(assets-lua-dir)]
                               (error (.. kind " target requires at least one --root")))
                           parsed.roots))
        {:kind kind
         :name (if (= kind :repo) "repo" (base-name (. root-list 1)))
         :roots root-list
         :files []
         :module-roots root-list
         :suites (default-suites)})))

M
