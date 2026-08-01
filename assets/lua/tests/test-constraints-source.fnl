(local tests [])
(local fs (require :fs))

(var temp-counter 0)
(local temp-root (fs.join-path "/tmp/space/tests" "constraints-source-test"))

(fn temp-dir-name []
  (set temp-counter (+ temp-counter 1))
  (fs.join-path temp-root (.. "test-" (os.time) "-" temp-counter)))

(fn make-file [dir name content]
  "Create a file in dir with given name and content."
  (local path (fs.join-path dir name))
  (fs.write-file path content)
  path)

(fn with-temp-dir [f]
  (local dir (temp-dir-name))
  (when (fs.exists dir)
    (fs.remove-all dir))
  (fs.create-dirs dir)
  (local (ok result) (pcall f dir))
  (fs.remove-all dir)
  (if ok
      result
      (error result)))

;; --- Target resolution tests ---

(fn targets-resolve-defaults-to-repo []
  (local Targets (require :constraints.targets))
  (local result (Targets.resolve [] {}))
  (assert (= result.kind :repo) (.. "expected :repo, got " (tostring result.kind)))
  (assert (= result.name "repo") "default target name should be repo")
  (assert result.roots "should have roots")
  (assert (> (# result.roots) 0) "roots should not be empty")
  ;; At least one root should contain assets/lua
  (var found false)
  (each [_ root (ipairs result.roots)]
    (when (or (string.find root "assets/lua" 1 true)
              (string.find root "assets" 1 true))
      (set found true)))
  (assert found "roots should include assets/lua")
  (assert result.suites "should have suites")
  ;; All four families should be present
  (local suite-set {})
  (each [_ s (ipairs result.suites)]
    (tset suite-set s true))
  (assert (. suite-set :scene-sandbox) "suites should include :scene-sandbox")
  (assert (. suite-set :lifecycle) "suites should include :lifecycle")
  (assert (. suite-set :test-isolation) "suites should include :test-isolation")
  (assert (. suite-set :layout-rendering) "suites should include :layout-rendering")
  (assert (. suite-set :structure-formatting) "suites should include :structure-formatting")
  (assert result.module-roots "should have module-roots"))

(fn targets-resolve-unit-with-root []
  (local Targets (require :constraints.targets))
  (local result (Targets.resolve ["--target" "unit"
                                   "--root" "/tmp/space/constraints-unit"] {}))
  (assert (= result.kind :unit) (.. "expected :unit, got " (tostring result.kind)))
  (assert result.name "unit target should have a name")
  (assert result.roots "unit target should have roots")
  (assert (> (# result.roots) 0) "unit root list should not be empty")
  ;; Check that --root value is reflected
  (var found-root false)
  (each [_ root (ipairs result.roots)]
    (when (string.find root "constraints-unit" 1 true)
      (set found-root true)))
  (assert found-root "unit roots should include constraints-unit"))

(fn targets-resolve-app-with-root []
  (local Targets (require :constraints.targets))
  (local result (Targets.resolve ["--target" "app"
                                   "--root" "/tmp/space/constraints-app"] {}))
  (assert (= result.kind :app) (.. "expected :app, got " (tostring result.kind)))
  (assert result.name "app target should have a name")
  (assert result.roots "app target should have roots")
  (var found-root false)
  (each [_ root (ipairs result.roots)]
    (when (string.find root "constraints-app" 1 true)
      (set found-root true)))
  (assert found-root "app roots should include constraints-app"))

(fn targets-resolve-files-with-file []
  (local Targets (require :constraints.targets))
  (local result (Targets.resolve ["--target" "files"
                                   "--file" "/tmp/space/constraints-one.fnl"] {}))
  (assert (= result.kind :files) (.. "expected :files, got " (tostring result.kind)))
  (assert result.files "files target should have files list")
  (assert (> (# result.files) 0) "files list should not be empty")
  (assert (= (. result.files 1) "/tmp/space/constraints-one.fnl")
          "files list should contain the specified file"))

(fn targets-resolve-refuses-unsupported-target []
  (local Targets (require :constraints.targets))
  (local (ok err) (pcall #(Targets.resolve ["--target" "bogus"] {})))
  (assert (not ok) "should fail for unsupported target")
  (assert (string.find (tostring err) "unsupported" 1 true)
          "error should mention unsupported"))

(fn targets-resolve-refuses-missing-target-value []
  (local Targets (require :constraints.targets))
  (local (ok err) (pcall #(Targets.resolve ["--target"] {})))
  (assert (not ok) "should fail when --target has no value"))

(fn targets-resolve-refuses-missing-root-for-unit []
  (local Targets (require :constraints.targets))
  (local (ok err) (pcall #(Targets.resolve ["--target" "unit"] {})))
  (assert (not ok) "should fail when unit target has no --root"))

(fn targets-resolve-refuses-unknown-flag []
  (local Targets (require :constraints.targets))
  (local (ok err) (pcall #(Targets.resolve ["--traget" "files" "--file" "/tmp/bad.fnl"] {})))
  (assert (not ok) "should fail for an unrecognized flag")
  (assert (string.find (tostring err) "unrecognized flag" 1 true)
          (.. "error should mention unrecognized flag, got: " (tostring err))))

(fn targets-resolve-refuses-stray-positional []
  (local Targets (require :constraints.targets))
  (local (ok err) (pcall #(Targets.resolve ["--target" "files" "stray" "--file" "/tmp/bad.fnl"] {})))
  (assert (not ok) "should fail for a stray positional argument")
  (assert (string.find (tostring err) "unexpected positional argument" 1 true)
          (.. "error should mention positional argument, got: " (tostring err))))

;; --- Source discovery tests ---

(fn source-discovers-fnl-files-recursively []
  (with-temp-dir (fn [dir]
    (local subdir (fs.join-path dir "sub"))
    (fs.create-dirs subdir)
    (make-file dir "alpha.fnl" "(print :alpha)")
    (make-file subdir "beta.fnl" "(print :beta)")
    (make-file dir "readme.txt" "text file")
    (local target {:kind :unit :name "test-unit" :roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (local paths {})
    (each [_ r (ipairs records)]
      (tset paths r.path true))
    (assert (. paths (fs.absolute (fs.join-path dir "alpha.fnl"))) "alpha.fnl should be discovered")
    (assert (. paths (fs.absolute (fs.join-path subdir "beta.fnl"))) "sub/beta.fnl should be discovered")
    (assert (not (. paths (fs.join-path dir "readme.txt"))) "readme.txt should be excluded")
    (assert (= (# records) 2) (.. "expected 2 records, got " (# records))))))

(fn source-excludes-non-fennel-files []
  (with-temp-dir (fn [dir]
    (make-file dir "code.fnl" "(+ 1 2)")
    (make-file dir "config.lua" "return {}")
    (make-file dir "notes.md" "# notes")
    (local target {:kind :unit :name "filter-test" :roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 fennel record, got " (# records)))
    (assert (= (fs.parent (. records 1 :path)) dir)))))

(fn source-parses-files-with-tree-sitter []
  (with-temp-dir (fn [dir]
    (make-file dir "sample.fnl" "(fn add [a b]\n  (+ a b))\n")
    (local target {:kind :unit :name "parse-test" :roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) "should discover one file")
    (local r (. records 1))
    (assert r.tree "file record should have a tree")
    (assert r.root "file record should have a root node")
    (assert (not (r.root:is-null)) "root node should not be null")
    (assert (> (r.root:child-count) 0) "root should have children"))))

(fn source-files-outside-assets-lua-parse-and-retain-target []
  (with-temp-dir (fn [dir]
    (local file-path (make-file dir "external.fnl" "(+ 1 2)"))
    (local target {:kind :files
                    :name "external-files"
                    :files [file-path]
                    :roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) "should discover the external file")
    (local r (. records 1))
    (assert (= r.path (fs.absolute file-path)) "path should match the absolute original file")
    (assert r.target "record should retain target")
    (assert (= r.target.kind :files) "target kind should be :files")
    (assert (= r.target.name "external-files") "target name should be preserved")
    (assert r.tree "external file should have a parsed tree"))))

(fn source-node-text-returns-substring []
  (with-temp-dir (fn [dir]
    (make-file dir "sample.fnl" "(fn hello [name]\n  (print name))\n")
    (local target {:kind :unit :name "node-text-test" :roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (local r (. records 1))
    ;; Grab a child node and verify node-text extracts correct substring
    (local root r.root)
    (assert (> (root:child-count) 0) "root should have children")
    (local child (root:child 0))
    (local text (Source.node-text r.source child))
    (assert text "node-text should return a non-empty string")
    (assert (> (# text) 0) "node-text should return something"))))

(fn source-node-location-returns-line-and-column []
  (with-temp-dir (fn [dir]
    (make-file dir "sample.fnl" "(fn hello [name]\n  (print name))\n")
    (local target {:kind :unit :name "loc-test" :roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (local r (. records 1))
    (local loc (Source.node-location r.root))
    (assert loc "node-location should return a table")
    (assert (= (. loc :line) 1)
            (.. "root should start on one-based line 1, got " (tostring (. loc :line))))
    (assert (= (. loc :column) 1)
            (.. "root should start on one-based column 1, got " (tostring (. loc :column)))))))

(fn source-walk-visits-all-nodes-depth-first []
  (with-temp-dir (fn [dir]
    (make-file dir "sample.fnl" "(print :hello)")
    (local target {:kind :unit :name "walk-test" :roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (local r (. records 1))
    (var visited 0)
    (Source.walk r.root (fn [_node] (set visited (+ visited 1))))
    (assert (> visited 1) (.. "walk should visit more than 1 node, got " visited)))))

;; --- Multiple --root tests ---

(fn targets-resolve-repeated-root []
  (local Targets (require :constraints.targets))
  (local result (Targets.resolve ["--target" "unit"
                                   "--root" "/tmp/space/constraints-r1"
                                   "--root" "/tmp/space/constraints-r2"] {}))
  (assert (= result.kind :unit) "kind should be :unit")
  (assert (= (# result.roots) 2) (.. "expected 2 roots, got " (# result.roots))))

;; --- Module name computation tests (R1-1) ---

(fn source-computes-module-name-from-root []
  "A file under a module root should produce a dotted module name (no .fnl, / -> .)"
  (with-temp-dir (fn [dir]
    (local subdir (fs.join-path dir "foo"))
    (fs.create-dirs subdir)
    (make-file subdir "bar.fnl" "(+ 1 2)")
    (local target {:kind :unit :name "module-test" :roots [dir] :module-roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 record, got " (# records)))
    (local r (. records 1))
    (assert r.module "record should have :module")
    (assert (= (type r.module) :string) "module should be a string")
    (assert (= r.module "foo.bar")
            (.. "expected module 'foo.bar', got '" (tostring r.module) "'")))))

(fn source-computes-module-name-for-init-fnl []
  "init.fnl files should produce a module name ending in .init"
  (with-temp-dir (fn [dir]
    (local subdir (fs.join-path dir "baz"))
    (fs.create-dirs subdir)
    (make-file subdir "init.fnl" "(+ 1 2)")
    (local target {:kind :unit :name "init-test" :roots [dir] :module-roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 record, got " (# records)))
    (local r (. records 1))
    (assert r.module "record should have :module")
    (assert (= r.module "baz.init")
            (.. "expected module 'baz.init', got '" (tostring r.module) "'")))))

(fn source-first-matching-root-wins-for-overlap []
  "Overlapping module roots: [root, root/foo] with file root/foo/bar.fnl
  should yield module 'foo.bar' (first match), NOT 'bar' (second overwrite)."
  (with-temp-dir (fn [dir]
    (local subdir (fs.join-path dir "foo"))
    (fs.create-dirs subdir)
    (make-file subdir "bar.fnl" "(+ 1 2)")
    ;; Overlapping roots: dir and dir/foo both match
    (local target {:kind :unit :name "overlap-test"
                    :roots [dir] :module-roots [dir subdir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 record, got " (# records)))
    (local r (. records 1))
    (assert r.module "record should have :module")
    (assert (= r.module "foo.bar")
            (.. "expected first-match module 'foo.bar', got '" (tostring r.module) "'")))))

;; --- Relative path computation tests (R1-1 path portability) ---

(fn source-computes-relative-path-from-module-root []
  "File records should include a portable :relative-path under the module root."
  (with-temp-dir (fn [dir]
    (local subdir (fs.join-path dir "nested"))
    (fs.create-dirs subdir)
    (make-file subdir "deep.fnl" "(+ 1 2)")
    (local target {:kind :unit :name "relpath-test" :roots [dir] :module-roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 record, got " (# records)))
    (local r (. records 1))
    (assert r.relative-path "record should have :relative-path")
    (assert (= (type r.relative-path) :string) "relative-path should be a string")
    (assert (= r.relative-path "nested/deep.fnl")
            (.. "expected 'nested/deep.fnl', got '" (tostring r.relative-path) "'")))))

(fn source-relative-path-falls-back-to-absolute []
  "When no module root matches, :relative-path should be the absolute path."
  (with-temp-dir (fn [dir]
    (make-file dir "orphan.fnl" "(+ 1 2)")
    (local target {:kind :unit :name "orphan-test" :roots [dir] :module-roots []})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 record, got " (# records)))
    (local r (. records 1))
    (assert r.relative-path "record should have :relative-path even with no module root")
    ;; With empty module-roots, relative-path should equal path
    (assert (= r.relative-path r.path)
            (.. "expected relative-path to equal path when no module root matches, got "
                (tostring r.relative-path) " vs " (tostring r.path))))))

(fn source-relative-path-uses-forward-slashes []
  "Relative paths produced by source discovery must always use forward slashes,
  regardless of the platform's native path separator."
  (with-temp-dir (fn [dir]
    (local subdir (fs.join-path dir "nested"))
    (fs.create-dirs subdir)
    (make-file subdir "deep.fnl" "(+ 1 2)")
    (local target {:kind :unit :name "slash-test" :roots [dir] :module-roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 record, got " (# records)))
    (local r (. records 1))
    (assert (not (string.find r.relative-path "\\" 1 true))
            (.. "relative-path must not contain backslash, got: " (tostring r.relative-path)))
    (assert (not (string.find r.module "\\" 1 true))
            (.. "module must not contain backslash, got: " (tostring r.module))))))

(fn source-module-uses-dots-not-slashes []
  "Module names derived from file paths must use dots as separators
  and must never contain forward slashes or backslashes."
  (with-temp-dir (fn [dir]
    (local subdir (fs.join-path dir "core"))
    (fs.create-dirs subdir)
    (make-file subdir "utils.fnl" "(+ 1 2)")
    (local target {:kind :unit :name "module-slash-test" :roots [dir] :module-roots [dir]})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1) (.. "expected 1 record, got " (# records)))
    (local r (. records 1))
    (assert (= r.module "core.utils")
            (.. "expected module 'core.utils', got '" (tostring r.module) "'"))
    (assert (not (string.find r.module "/" 1 true))
            (.. "module must not contain forward slash, got: " (tostring r.module)))
    (assert (not (string.find r.module "\\" 1 true))
            (.. "module must not contain backslash, got: " (tostring r.module))))))

;; --- Non-Fennel explicit file tests (R1-2) ---

(fn source-files-target-rejects-non-fennel-paths []
  "Explicit --file paths that are not .fnl should be excluded from discovery."
  (with-temp-dir (fn [dir]
    (local txt-path (make-file dir "readme.txt" "hello"))
    (local target {:kind :files
                    :name "file-filter"
                    :files [txt-path]
                    :roots []})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 0)
            (.. "expected 0 records for non-fnl explicit file, got " (# records))))))

(fn source-files-target-includes-fennel-and-excludes-others []
  "Mixed explicit files: .fnl should be included, non-.fnl excluded."
  (with-temp-dir (fn [dir]
    (local fnl-path (make-file dir "code.fnl" "(+ 1 2)"))
    (local txt-path (make-file dir "notes.txt" "text"))
    (local target {:kind :files
                    :name "mixed-files"
                    :files [fnl-path txt-path]
                    :roots []})
    (local Source (require :constraints.source))
    (local records (Source.discover target))
    (assert (= (# records) 1)
            (.. "expected 1 fennel record, got " (# records)))
    (local r (. records 1))
    (assert (= r.path fnl-path) "only .fnl file should be discovered"))))

;; --- Missing/unreadable root tests (R1-3) ---

(fn source-fails-loudly-on-nonexistent-root []
  "A target root that does not exist should cause discovery to fail, not silently skip."
  (with-temp-dir (fn [dir]
    (local missing-root (fs.join-path dir "does-not-exist"))
    (local target {:kind :unit :name "broken" :roots [missing-root]})
    (local Source (require :constraints.source))
    (local (ok err) (pcall #(Source.discover target)))
    (assert (not ok)
            "discover should fail for missing root, not silently skip")
    (assert (string.find (tostring err) missing-root 1 true)
            (.. "error should mention the missing root path, got: " (tostring err))))))

;; --- Repeated --file tests ---

(fn targets-resolve-repeated-file []
  (local Targets (require :constraints.targets))
  (local result (Targets.resolve ["--target" "files"
                                   "--file" "/tmp/a.fnl"
                                   "--file" "/tmp/b.fnl"] {}))
  (assert (= result.kind :files) "kind should be :files")
  (assert (= (# result.files) 2) (.. "expected 2 files, got " (# result.files))))

;; Register all tests
(table.insert tests {:name "targets resolve defaults to repo"
                     :fn targets-resolve-defaults-to-repo})
(table.insert tests {:name "targets resolve unit with --root"
                     :fn targets-resolve-unit-with-root})
(table.insert tests {:name "targets resolve app with --root"
                     :fn targets-resolve-app-with-root})
(table.insert tests {:name "targets resolve files with --file"
                     :fn targets-resolve-files-with-file})
(table.insert tests {:name "targets resolve refuses unsupported target"
                     :fn targets-resolve-refuses-unsupported-target})
(table.insert tests {:name "targets resolve refuses missing target value"
                     :fn targets-resolve-refuses-missing-target-value})
(table.insert tests {:name "targets resolve refuses missing root for unit"
                      :fn targets-resolve-refuses-missing-root-for-unit})
(table.insert tests {:name "targets resolve refuses unknown flag"
                      :fn targets-resolve-refuses-unknown-flag})
(table.insert tests {:name "targets resolve refuses stray positional"
                      :fn targets-resolve-refuses-stray-positional})
(table.insert tests {:name "source discovers fnl files recursively"
                     :fn source-discovers-fnl-files-recursively})
(table.insert tests {:name "source excludes non-fennel files"
                     :fn source-excludes-non-fennel-files})
(table.insert tests {:name "source parses files with tree-sitter"
                     :fn source-parses-files-with-tree-sitter})
(table.insert tests {:name "source files outside assets/lua parse and retain target"
                     :fn source-files-outside-assets-lua-parse-and-retain-target})
(table.insert tests {:name "source node-text returns substring"
                     :fn source-node-text-returns-substring})
(table.insert tests {:name "source node-location returns line and column"
                     :fn source-node-location-returns-line-and-column})
(table.insert tests {:name "source walk visits all nodes depth-first"
                     :fn source-walk-visits-all-nodes-depth-first})
(table.insert tests {:name "source computes module name from root"
                     :fn source-computes-module-name-from-root})
(table.insert tests {:name "source computes module name for init.fnl"
                     :fn source-computes-module-name-for-init-fnl})
(table.insert tests {:name "source first matching root wins for overlap"
                      :fn source-first-matching-root-wins-for-overlap})
(table.insert tests {:name "source computes relative path from module root (R1-1)"
                      :fn source-computes-relative-path-from-module-root})
(table.insert tests {:name "source relative path falls back to absolute (R1-1)"
                      :fn source-relative-path-falls-back-to-absolute})
(table.insert tests {:name "source relative path uses forward slashes"
                      :fn source-relative-path-uses-forward-slashes})
(table.insert tests {:name "source module uses dots not slashes"
                      :fn source-module-uses-dots-not-slashes})
(table.insert tests {:name "source files target rejects non-fennel paths"
                     :fn source-files-target-rejects-non-fennel-paths})
(table.insert tests {:name "source files target includes fennel and excludes others"
                     :fn source-files-target-includes-fennel-and-excludes-others})
(table.insert tests {:name "source fails loudly on nonexistent root"
                     :fn source-fails-loudly-on-nonexistent-root})
(table.insert tests {:name "targets resolve repeated --root"
                     :fn targets-resolve-repeated-root})
(table.insert tests {:name "targets resolve repeated --file"
                     :fn targets-resolve-repeated-file})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "constraints-source"
                        :tests tests})))

{:name "constraints-source"
 :tests tests
 :main main}
