(local random (require :random))
(local fs (require :fs))
(local appdirs (require :appdirs))

(local default-prefix "tmp")
(local default-suffix "")

(fn gettempdir []
  (appdirs.tmp-dir))

(fn option-or-default [opts key default]
  (if (and opts (not= (. opts key) nil))
      (. opts key)
      default))

(fn build-options [opts defaults]
  (local options (or opts {}))
  {:prefix (option-or-default options :prefix defaults.prefix)
   :suffix (option-or-default options :suffix defaults.suffix)
   :dir (option-or-default options :dir defaults.dir)
   :delete (option-or-default options :delete defaults.delete)})

(fn generate-name [prefix suffix]
  (.. prefix (random.randbytes-hex 8) suffix))

(fn mkstemp [opts]
  (local defaults {:prefix default-prefix
                   :suffix default-suffix
                   :dir (gettempdir)
                   :delete true})
  (local options (build-options opts defaults))
  (fs.create-dirs options.dir)
  (var attempt 0)
  (var created-path nil)
  (while (and (< attempt 10) (not created-path))
    (set attempt (+ attempt 1))
    (local name (generate-name options.prefix options.suffix))
    (local path (fs.join-path options.dir name))
    (when (not (fs.exists path))
      (fs.write-file path "")
      (set created-path path)))
  (if created-path
      created-path
      (error "tempfile.mkstemp failed to create a unique file after 10 attempts")))

(fn mkdtemp [opts]
  (local defaults {:prefix default-prefix
                   :suffix default-suffix
                   :dir (gettempdir)
                   :delete true})
  (local options (build-options opts defaults))
  (fs.create-dirs options.dir)
  (var attempt 0)
  (var created-path nil)
  (while (and (< attempt 10) (not created-path))
    (set attempt (+ attempt 1))
    (local name (generate-name options.prefix options.suffix))
    (local path (fs.join-path options.dir name))
    (when (not (fs.exists path))
      (local created (fs.create-dir path))
      (when created
        (set created-path path))))
  (if created-path
      created-path
      (error "tempfile.mkdtemp failed to create a unique directory after 10 attempts")))

(fn NamedTemporaryFile [opts]
  (local defaults {:prefix default-prefix
                   :suffix default-suffix
                   :dir (gettempdir)
                   :delete true})
  (local options (build-options opts defaults))
  (local path (mkstemp options))
  (var dropped false)
  (local drop
    (fn [_self]
      (when (not dropped)
        (set dropped true)
        (when (and options.delete (fs.exists path))
          (fs.remove path)))))
  {:path path
   :drop drop})

(fn TemporaryDirectory [opts]
  (local defaults {:prefix default-prefix
                   :suffix default-suffix
                   :dir (gettempdir)
                   :delete true})
  (local options (build-options opts defaults))
  (local path (mkdtemp options))
  (var dropped false)
  (local drop
    (fn [_self]
      (when (not dropped)
        (set dropped true)
        (when (fs.exists path)
          (fs.remove-all path)))))
  {:path path
   :drop drop})

{:gettempdir gettempdir
 :mkstemp mkstemp
 :mkdtemp mkdtemp
 :NamedTemporaryFile NamedTemporaryFile
 :TemporaryDirectory TemporaryDirectory}
