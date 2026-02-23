(local process (require :process))
(local fs (require :fs))

(fn is-array? [value]
  (if (not (= (type value) :table))
      false
      (do
        (var max 0)
        (var count 0)
        (each [k _ (pairs value)]
          (if (or (not (= (type k) :number))
                  (not (= k (math.floor k)))
                  (< k 1))
              (lua "return false")
              (do
                (set count (+ count 1))
                (when (> k max)
                  (set max k)))))
        (= count max))))

(fn assert-string-array [name value]
  (when (not (is-array? value))
    (error (.. "native-build " name " must be an array")))
  (each [_ item (ipairs value)]
    (when (not (= (type item) :string))
      (error (.. "native-build " name " entries must be strings")))))

(fn append-array! [target items]
  (each [_ v (ipairs items)]
    (table.insert target v))
  target)

(fn append-prefixed! [target prefix items]
  (each [_ value (ipairs items)]
    (table.insert target (.. prefix value)))
  target)

(fn starts-with? [value prefix]
  (= (string.sub value 1 (# prefix)) prefix))

(fn ends-with? [value suffix]
  (if (= suffix "")
      true
      (= (string.sub value (- (# value) (# suffix) -1)) suffix)))

(fn basename [path]
  (local name (string.match path "([^/\\]+)$"))
  (if name name path))

(fn detect-platform []
  (local separator (string.sub package.config 1 1))
  (if (= separator "\\")
      :windows
      (do
        (local uname (process.run {:args ["uname" "-s"] :timeout 1}))
        (if (and (= uname.exit-code 0)
                 (starts-with? uname.stdout "Darwin"))
            :macos
            :linux))))

(fn platform-shared-extension [platform]
  (if (= platform :windows)
      ".dll"
      (= platform :macos)
      ".dylib"
      ".so"))

(fn platform-exe-extension [platform]
  (if (= platform :windows) ".exe" ""))

(fn ensure-dir! [path]
  (fs.create-dirs path)
  path)

(fn join-args [args]
  (table.concat args " "))

(fn command-summary [label args]
  (.. label " [" (join-args args) "]"))

(fn maybe-log [verbose label args]
  (when verbose
    (print (.. "[native-build] " (command-summary label args)))))

(fn format-result-error [label args result]
  (.. "native-build command failed: "
      (command-summary label args)
      "\nexit-code: " (tostring result.exit-code)
      "\nstdout:\n" (or result.stdout "")
      "\nstderr:\n" (or result.stderr "")))

(fn assert-success! [label args result]
  (when (not (= result.exit-code 0))
    (error (format-result-error label args result)))
  result)

(fn run-command! [spec label verbose]
  (maybe-log verbose label spec.args)
  (local result (process.run spec))
  (assert-success! label spec.args result))

(fn spawn-command [spec label verbose on-success]
  (maybe-log verbose label spec.args)
  (local id (process.spawn spec))
  {:id id
   :running (fn [self]
              (process.running self.id))
   :kill (fn [self signal]
           (process.kill self.id (or signal 15)))
   :wait (fn [self]
           (local result (process.wait self.id))
           (assert-success! label spec.args result)
           (if on-success
               (on-success result)
               result))})

(fn build-common-flags [opts]
  (local options (or opts {}))
  (local out [])
  (when options.standard
    (table.insert out (.. "-std=" options.standard)))
  (when (not (= options.optimization nil))
    (table.insert out (.. "-O" (tostring options.optimization))))
  (append-array! out (or options.flags []))
  out)

(fn assert-path-array [name value]
  (assert-string-array name value)
  value)

(fn resolve-max-parallel [default-value override]
  (local value (if (not (= override nil)) override default-value))
  (if (= value nil)
      nil
      (do
        (when (or (not (= (type value) :number))
                  (not (= value (math.floor value)))
                  (< value 1))
          (error "native-build :max-parallel must be an integer >= 1"))
        value)))

(fn compile-object-output [location source opts]
  (local options (or opts {}))
  (local extension (or options.object-extension ".o"))
  (local source-name (basename source))
  (fs.join-path location (.. source-name extension)))

(fn normalize-shared-out [out opts]
  (local options (or opts {}))
  (local extension (or options.shared-extension (platform-shared-extension (detect-platform))))
  (if (ends-with? out extension)
      out
      (.. out extension)))

(fn normalize-executable-out [out opts]
  (local options (or opts {}))
  (local extension (or options.executable-extension (platform-exe-extension (detect-platform))))
  (if (or (= extension "") (ends-with? out extension))
      out
      (.. out extension)))

(fn normalize-archive-out [out opts]
  (local options (or opts {}))
  (local extension (or options.archive-extension ".a"))
  (if (ends-with? out extension)
      out
      (.. out extension)))

(fn GCCCompiler [opts]
  (local options (or opts {}))
  (local program (or options.program "g++"))
  (local common-flags (build-common-flags options))
  (local verbose (or options.verbose false))
  (local max-parallel (resolve-max-parallel nil options.max-parallel))
  (local self
    {:program program
     :verbose verbose
     :max-parallel max-parallel
     :flags common-flags
     :build (fn [self out files opts]
              (local cfg (or opts {}))
              (assert-path-array ":files" files)
              (local args [self.program])
              (append-array! args self.flags)
              (append-array! args (or cfg.extra-compile-flags []))
              (table.insert args "-o")
              (table.insert args (normalize-executable-out out cfg))
              (append-array! args files)
              (append-prefixed! args "-I" (or cfg.includes []))
              (append-prefixed! args "-L" (or cfg.link-paths []))
              (append-prefixed! args "-l" (or cfg.shared-libraries []))
              (append-array! args (or cfg.static-libraries []))
              (append-array! args (or cfg.extra-linker-flags []))
              (run-command! {:args args :cwd cfg.cwd :env cfg.env}
                            "link executable"
                            self.verbose)
              (normalize-executable-out out cfg))
     :build-async (fn [self out files opts]
                    (local cfg (or opts {}))
                    (assert-path-array ":files" files)
                    (local args [self.program])
                    (append-array! args self.flags)
                    (append-array! args (or cfg.extra-compile-flags []))
                    (table.insert args "-o")
                    (table.insert args (normalize-executable-out out cfg))
                    (append-array! args files)
                    (append-prefixed! args "-I" (or cfg.includes []))
                    (append-prefixed! args "-L" (or cfg.link-paths []))
                    (append-prefixed! args "-l" (or cfg.shared-libraries []))
                    (append-array! args (or cfg.static-libraries []))
                    (append-array! args (or cfg.extra-linker-flags []))
                    (local final-out (normalize-executable-out out cfg))
                    (spawn-command {:args args :cwd cfg.cwd :env cfg.env}
                                   "link executable"
                                   self.verbose
                                   (fn [_result] final-out)))
     :build-to-objects (fn [self location files opts]
                         (local cfg (or opts {}))
                         (assert-path-array ":files" files)
                         (ensure-dir! location)
                         (local out [])
                         (each [_ file (ipairs files)]
                           (local object-file (compile-object-output location file cfg))
                           (local args [self.program])
                           (append-array! args self.flags)
                           (append-array! args (or cfg.extra-compile-flags []))
                           (table.insert args "-c")
                           (table.insert args "-o")
                           (table.insert args object-file)
                           (table.insert args file)
                           (append-prefixed! args "-I" (or cfg.includes []))
                           (run-command! {:args args :cwd cfg.cwd :env cfg.env}
                                         "compile object"
                                         self.verbose)
                           (table.insert out object-file))
                         out)
     :build-to-objects-async (fn [self location files opts]
                               (local cfg (or opts {}))
                               (assert-path-array ":files" files)
                               (ensure-dir! location)
                               (local jobs [])
                               (local object-files [])
                               (local parallel-limit (resolve-max-parallel self.max-parallel cfg.max-parallel))
                               (each [_ file (ipairs files)]
                                 (local object-file (compile-object-output location file cfg))
                                 (table.insert object-files object-file)
                                 (local args [self.program])
                                 (append-array! args self.flags)
                                 (append-array! args (or cfg.extra-compile-flags []))
                                 (table.insert args "-c")
                                 (table.insert args "-o")
                                 (table.insert args object-file)
                                 (table.insert args file)
                                 (append-prefixed! args "-I" (or cfg.includes []))
                                 (table.insert jobs {:label "compile object"
                                                     :args args
                                                     :id nil}))
                               (local launch-up-to
                                 (fn [token]
                                   (while (and (<= token.next-index (# token.jobs))
                                               (or (= token.max-parallel nil)
                                                   (< (# token.active) token.max-parallel)))
                                     (local idx token.next-index)
                                     (local job (. token.jobs idx))
                                     (when self.verbose
                                       (maybe-log true job.label job.args))
                                     (set job.id (process.spawn {:args job.args :cwd cfg.cwd :env cfg.env}))
                                     (table.insert token.active idx)
                                     (set token.next-index (+ token.next-index 1)))))
                               (local running?
                                 (fn [token]
                                   (if token.cancelled
                                       false
                                       (or (> (# token.active) 0)
                                           (<= token.next-index (# token.jobs))))))
                               (local kill!
                                 (fn [token signal]
                                   (set token.cancelled true)
                                   (var killed-any false)
                                   (each [_ idx (ipairs token.active)]
                                     (local job (. token.jobs idx))
                                     (when (and job.id (process.kill job.id (or signal 15)))
                                       (set killed-any true)))
                                   killed-any))
                               (local wait!
                                 (fn [token]
                                   (while (or (> (# token.active) 0)
                                              (<= token.next-index (# token.jobs)))
                                     (launch-up-to token)
                                     (when (> (# token.active) 0)
                                       (local idx (. token.active 1))
                                       (local job (. token.jobs idx))
                                       (local result (process.wait job.id))
                                       (assert-success! job.label job.args result)
                                       (table.remove token.active 1)))
                                   token.object-files))
                               (local token {})
                               (set token.running running?)
                               (set token.kill kill!)
                               (set token.wait wait!)
                               (set token.launch launch-up-to)
                               (set token.jobs jobs)
                               (set token.active [])
                               (set token.next-index 1)
                               (set token.max-parallel parallel-limit)
                               (set token.cancelled false)
                               (set token.object-files object-files)
                               (launch-up-to token)
                               token)
     :build-sharable-objects (fn [self location files opts]
                               (local cfg (or opts {}))
                               (local compile-flags (or cfg.extra-compile-flags []))
                               (self:build-to-objects location files {:cwd cfg.cwd
                                                                      :env cfg.env
                                                                      :includes (or cfg.includes [])
                                                                      :extra-compile-flags (append-array! ["-fPIC"] compile-flags)
                                                                      :object-extension (or cfg.object-extension ".o")
                                                                      :max-parallel cfg.max-parallel}))
     :build-sharable-objects-async (fn [self location files opts]
                                     (local cfg (or opts {}))
                                     (local compile-flags (or cfg.extra-compile-flags []))
                                     (self:build-to-objects-async location files {:cwd cfg.cwd
                                                                                  :env cfg.env
                                                                                  :includes (or cfg.includes [])
                                                                                  :extra-compile-flags (append-array! ["-fPIC"] compile-flags)
                                                                                  :object-extension (or cfg.object-extension ".o")
                                                                                  :max-parallel cfg.max-parallel}))
     :build-shared-object (fn [self out files opts]
                            (local cfg (or opts {}))
                            (assert-path-array ":files" files)
                            (local final-out (normalize-shared-out out cfg))
                            (local args [self.program])
                            (append-array! args self.flags)
                            (append-array! args (or cfg.extra-compile-flags []))
                            (table.insert args "-shared")
                            (append-array! args files)
                            (append-prefixed! args "-L" (or cfg.link-paths []))
                            (append-prefixed! args "-l" (or cfg.shared-libraries []))
                            (append-array! args (or cfg.static-libraries []))
                            (append-array! args (or cfg.extra-linker-flags []))
                            (table.insert args "-o")
                            (table.insert args final-out)
                            (run-command! {:args args :cwd cfg.cwd :env cfg.env}
                                          "link shared object"
                                          self.verbose)
                            final-out)
     :build-shared-object-async (fn [self out files opts]
                                  (local cfg (or opts {}))
                                  (assert-path-array ":files" files)
                                  (local final-out (normalize-shared-out out cfg))
                                  (local args [self.program])
                                  (append-array! args self.flags)
                                  (append-array! args (or cfg.extra-compile-flags []))
                                  (table.insert args "-shared")
                                  (append-array! args files)
                                  (append-prefixed! args "-L" (or cfg.link-paths []))
                                  (append-prefixed! args "-l" (or cfg.shared-libraries []))
                                  (append-array! args (or cfg.static-libraries []))
                                  (append-array! args (or cfg.extra-linker-flags []))
                                  (table.insert args "-o")
                                  (table.insert args final-out)
                                  (spawn-command {:args args :cwd cfg.cwd :env cfg.env}
                                                 "link shared object"
                                                 self.verbose
                                                 (fn [_result] final-out)))})
  self)

(fn Gpp [opts]
  (local options (or opts {}))
  (GCCCompiler {:program (or options.program "g++")
                :standard (or options.standard "c++17")
                :optimization (if (= options.optimization nil) 2 options.optimization)
                :flags (or options.flags [])
                :verbose (or options.verbose false)
                :max-parallel options.max-parallel}))

(fn Gcc [opts]
  (local options (or opts {}))
  (GCCCompiler {:program (or options.program "gcc")
                :standard (or options.standard "c17")
                :optimization (if (= options.optimization nil) 2 options.optimization)
                :flags (or options.flags [])
                :verbose (or options.verbose false)
                :max-parallel options.max-parallel}))

(fn Ar [opts]
  (local options (or opts {}))
  (local program (or options.program "ar"))
  (local verbose (or options.verbose false))
  (local self
    {:program program
     :verbose verbose
     :archive (fn [self out files opts]
                (local cfg (or opts {}))
                (assert-path-array ":files" files)
                (local final-out (normalize-archive-out out cfg))
                (local args [self.program "rcs" final-out])
                (append-array! args files)
                (run-command! {:args args :cwd cfg.cwd :env cfg.env}
                              "archive static library"
                              self.verbose)
                final-out)
     :archive-async (fn [self out files opts]
                      (local cfg (or opts {}))
                      (assert-path-array ":files" files)
                      (local final-out (normalize-archive-out out cfg))
                      (local args [self.program "rcs" final-out])
                      (append-array! args files)
                      (spawn-command {:args args :cwd cfg.cwd :env cfg.env}
                                     "archive static library"
                                     self.verbose
                                     (fn [_result] final-out)))})
  self)

(fn Project [opts]
  (local options (or opts {}))
  (local name options.name)
  (local compiler options.compiler)
  (local build-dir (or options.build-dir "__pysembled__"))
  (assert (and (= (type name) :string) (> (# name) 0))
          "native-build Project requires non-empty :name")
  (assert (and compiler compiler.build compiler.build-to-objects)
          "native-build Project requires :compiler")
  (ensure-dir! build-dir)
  (local platform (or options.platform (detect-platform)))
  (local verbose (or options.verbose false))
  (local self
    {:name name
     :compiler compiler
     :platform platform
     :verbose verbose
     :build-dir build-dir
     :executables []
     :static-libraries []
     :dynamic-libraries []
     :include-directories []
     :link-paths []
     :extra-compile-flags []
     :extra-linker-flags []
     :output-path (fn [self]
                    (normalize-executable-out self.name {:executable-extension (platform-exe-extension self.platform)}))
     :add-executable (fn [self path]
                       (table.insert self.executables path)
                       self)
     :add-executables (fn [self paths]
                        (assert-string-array ":executables" paths)
                        (append-array! self.executables paths)
                        self)
     :add-static-lib (fn [self path]
                       (table.insert self.static-libraries path)
                       self)
     :add-static-libs (fn [self paths]
                        (assert-string-array ":static-libraries" paths)
                        (append-array! self.static-libraries paths)
                        self)
     :add-dynamic-lib (fn [self name]
                        (table.insert self.dynamic-libraries name)
                        self)
     :add-dynamic-libs (fn [self names]
                         (assert-string-array ":dynamic-libraries" names)
                         (append-array! self.dynamic-libraries names)
                         self)
     :add-link-path (fn [self path]
                      (table.insert self.link-paths path)
                      self)
     :add-include-directory (fn [self path]
                              (table.insert self.include-directories path)
                              self)
     :add-compile-flag (fn [self flag]
                         (table.insert self.extra-compile-flags flag)
                         self)
     :add-linker-flag (fn [self flag]
                        (table.insert self.extra-linker-flags flag)
                        self)
     :build (fn [self opts]
              (local cfg (or opts {}))
              (when (= (# self.executables) 0)
                (error "native-build Project requires at least one executable source"))
              (local object-files
                (self.compiler:build-to-objects self.build-dir self.executables {:cwd cfg.cwd
                                                                                  :env cfg.env
                                                                                  :includes self.include-directories
                                                                                  :extra-compile-flags self.extra-compile-flags
                                                                                  :object-extension (or cfg.object-extension ".o")
                                                                                  :max-parallel cfg.max-parallel}))
              (local out (self:output-path))
              (self.compiler:build out object-files {:cwd cfg.cwd
                                                     :env cfg.env
                                                     :includes self.include-directories
                                                     :link-paths self.link-paths
                                                     :shared-libraries self.dynamic-libraries
                                                     :static-libraries self.static-libraries
                                                     :extra-linker-flags self.extra-linker-flags
                                                     :extra-compile-flags self.extra-compile-flags
                                                     :executable-extension (platform-exe-extension self.platform)})
              out)
     :build-async (fn [self opts]
                    (local cfg (or opts {}))
                    (when (= (# self.executables) 0)
                      (error "native-build Project requires at least one executable source"))
                    (local compile-token
                      (self.compiler:build-to-objects-async self.build-dir self.executables {:cwd cfg.cwd
                                                                                              :env cfg.env
                                                                                              :includes self.include-directories
                                                                                              :extra-compile-flags self.extra-compile-flags
                                                                                              :object-extension (or cfg.object-extension ".o")
                                                                                              :max-parallel cfg.max-parallel}))
                    {:running (fn [token]
                                (if token.link-token
                                    (token.link-token:running)
                                    (compile-token:running)))
                     :kill (fn [token signal]
                             (if token.link-token
                                 (token.link-token:kill signal)
                                 (compile-token:kill signal)))
                     :wait (fn [token]
                             (local objects (compile-token:wait))
                             (local out (self:output-path))
                             (set token.link-token
                                  (self.compiler:build-async out objects {:cwd cfg.cwd
                                                                          :env cfg.env
                                                                          :includes self.include-directories
                                                                          :link-paths self.link-paths
                                                                          :shared-libraries self.dynamic-libraries
                                                                          :static-libraries self.static-libraries
                                                                          :extra-linker-flags self.extra-linker-flags
                                                                          :extra-compile-flags self.extra-compile-flags
                                                                          :executable-extension (platform-exe-extension self.platform)}))
                             (token.link-token:wait))})
     :run (fn [self opts]
            (local cfg (or opts {}))
            (local args [(or cfg.program (self:output-path))])
            (append-array! args (or cfg.args []))
            (run-command! {:args args :cwd cfg.cwd :env cfg.env :stdin cfg.stdin}
                          "run executable"
                          (or cfg.verbose self.verbose)))})
  self)

(fn Library [opts]
  (local options (or opts {}))
  (local name options.name)
  (local compiler options.compiler)
  (local archiver options.archiver)
  (local build-dir (or options.build-dir "__pysembled__"))
  (assert (and (= (type name) :string) (> (# name) 0))
          "native-build Library requires non-empty :name")
  (assert (and compiler compiler.build-sharable-objects compiler.build-shared-object)
          "native-build Library requires :compiler")
  (assert (and archiver archiver.archive)
          "native-build Library requires :archiver")
  (ensure-dir! build-dir)
  (local platform (or options.platform (detect-platform)))
  (local self
    {:name name
     :compiler compiler
     :archiver archiver
     :build-dir build-dir
     :platform platform
     :sources []
     :headers []
     :include-directories []
     :extra-compile-flags []
     :extra-linker-flags []
     :static-extension ".a"
     :shared-extension (platform-shared-extension platform)
     :add-source (fn [self path]
                   (table.insert self.sources path)
                   self)
     :add-sources (fn [self paths]
                    (assert-string-array ":sources" paths)
                    (append-array! self.sources paths)
                    self)
     :add-header (fn [self path]
                   (table.insert self.headers path)
                   self)
     :add-headers (fn [self paths]
                    (assert-string-array ":headers" paths)
                    (append-array! self.headers paths)
                    self)
     :add-include-directory (fn [self path]
                              (table.insert self.include-directories path)
                              self)
     :add-compile-flag (fn [self flag]
                         (table.insert self.extra-compile-flags flag)
                         self)
     :add-linker-flag (fn [self flag]
                        (table.insert self.extra-linker-flags flag)
                        self)
     :build (fn [self opts]
              (local cfg (or opts {}))
              (when (= (# self.sources) 0)
                (error "native-build Library requires at least one source"))
              (local objects
                (self.compiler:build-to-objects self.build-dir self.sources {:cwd cfg.cwd
                                                                              :env cfg.env
                                                                              :includes self.include-directories
                                                                              :extra-compile-flags self.extra-compile-flags
                                                                              :object-extension (or cfg.object-extension ".o")
                                                                              :max-parallel cfg.max-parallel}))
              (self.archiver:archive (fs.join-path self.build-dir self.name)
                                     objects
                                     {:cwd cfg.cwd
                                      :env cfg.env
                                      :archive-extension self.static-extension}))
     :build-async (fn [self opts]
                    (local cfg (or opts {}))
                    (when (= (# self.sources) 0)
                      (error "native-build Library requires at least one source"))
                    (local compile-token
                      (self.compiler:build-to-objects-async self.build-dir self.sources {:cwd cfg.cwd
                                                                                          :env cfg.env
                                                                                          :includes self.include-directories
                                                                                          :extra-compile-flags self.extra-compile-flags
                                                                                          :object-extension (or cfg.object-extension ".o")
                                                                                          :max-parallel cfg.max-parallel}))
                    {:running (fn [token]
                                (if token.archive-token
                                    (token.archive-token:running)
                                    (compile-token:running)))
                     :kill (fn [token signal]
                             (if token.archive-token
                                 (token.archive-token:kill signal)
                                 (compile-token:kill signal)))
                     :wait (fn [token]
                             (local objects (compile-token:wait))
                             (set token.archive-token
                                  (self.archiver:archive-async (fs.join-path self.build-dir self.name)
                                                               objects
                                                               {:cwd cfg.cwd
                                                                :env cfg.env
                                                                :archive-extension self.static-extension}))
                             (token.archive-token:wait))})
     :build-shared (fn [self opts]
                     (local cfg (or opts {}))
                     (when (= (# self.sources) 0)
                       (error "native-build Library requires at least one source"))
                     (local objects
                       (self.compiler:build-sharable-objects self.build-dir self.sources {:cwd cfg.cwd
                                                                                           :env cfg.env
                                                                                           :includes self.include-directories
                                                                                           :extra-compile-flags self.extra-compile-flags
                                                                                           :object-extension (or cfg.object-extension ".o")
                                                                                           :max-parallel cfg.max-parallel}))
                     (self.compiler:build-shared-object (fs.join-path self.build-dir self.name)
                                                        objects
                                                        {:cwd cfg.cwd
                                                         :env cfg.env
                                                         :link-paths (or cfg.link-paths [])
                                                         :shared-libraries (or cfg.shared-libraries [])
                                                         :static-libraries (or cfg.static-libraries [])
                                                         :extra-linker-flags self.extra-linker-flags
                                                         :extra-compile-flags self.extra-compile-flags
                                                         :shared-extension self.shared-extension}))
     :build-shared-async (fn [self opts]
                           (local cfg (or opts {}))
                           (when (= (# self.sources) 0)
                             (error "native-build Library requires at least one source"))
                           (local compile-token
                             (self.compiler:build-sharable-objects-async self.build-dir self.sources {:cwd cfg.cwd
                                                                                                         :env cfg.env
                                                                                                         :includes self.include-directories
                                                                                                         :extra-compile-flags self.extra-compile-flags
                                                                                                         :object-extension (or cfg.object-extension ".o")
                                                                                                         :max-parallel cfg.max-parallel}))
                           {:running (fn [token]
                                       (if token.link-token
                                           (token.link-token:running)
                                           (compile-token:running)))
                            :kill (fn [token signal]
                                    (if token.link-token
                                        (token.link-token:kill signal)
                                        (compile-token:kill signal)))
                            :wait (fn [token]
                                    (local objects (compile-token:wait))
                                    (set token.link-token
                                         (self.compiler:build-shared-object-async (fs.join-path self.build-dir self.name)
                                                                                  objects
                                                                                  {:cwd cfg.cwd
                                                                                   :env cfg.env
                                                                                   :link-paths (or cfg.link-paths [])
                                                                                   :shared-libraries (or cfg.shared-libraries [])
                                                                                   :static-libraries (or cfg.static-libraries [])
                                                                                   :extra-linker-flags self.extra-linker-flags
                                                                                   :extra-compile-flags self.extra-compile-flags
                                                                                   :shared-extension self.shared-extension}))
                                    (token.link-token:wait))})
     :package (fn [self opts]
                (local cfg (or opts {}))
                (when (= (# self.headers) 0)
                  (error "native-build Library.package requires at least one header"))
                (local package-dir (or cfg.package-dir self.name))
                (local lib-path (fs.join-path package-dir "lib"))
                (local include-path (fs.join-path package-dir "include"))
                (when (fs.exists package-dir)
                  (fs.remove-all package-dir))
                (fs.create-dirs lib-path)
                (fs.create-dirs include-path)
                (each [_ header (ipairs self.headers)]
                  (local filename (basename header))
                  (local target (fs.join-path include-path filename))
                  (fs.write-file target (fs.read-file header)))
                (if cfg.dynamic
                    (do
                      (local shared-path (self:build-shared opts))
                      (local shared-name (basename shared-path))
                      (fs.write-file (fs.join-path lib-path shared-name) (fs.read-file shared-path))
                      {:root package-dir
                       :include include-path
                       :lib lib-path
                       :artifact (fs.join-path lib-path shared-name)})
                    (do
                      (local static-path (self:build opts))
                      (local static-name (basename static-path))
                      (fs.write-file (fs.join-path lib-path static-name) (fs.read-file static-path))
                      {:root package-dir
                       :include include-path
                       :lib lib-path
                       :artifact (fs.join-path lib-path static-name)})))})
  self)

{:Gcc Gcc
 :Gpp Gpp
 :Ar Ar
 :Project Project
 :Library Library
 :detect-platform detect-platform
 :platform-shared-extension platform-shared-extension
 :platform-exe-extension platform-exe-extension}
