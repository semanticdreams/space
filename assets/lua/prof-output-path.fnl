(local os os)
(local string string)

(local ProfOutputPath {})

(fn to-lower [value]
  (and value (string.lower value)))

(fn use-default-output? [value]
  (local lower (to-lower value))
  (or (= value nil)
      (= value "")
      (= value "1")
      (= lower "true")
      (= lower "on")))

(fn flamegraph-disabled? [value]
  (local lower (to-lower value))
  (and value (or (= value "0")
                 (= lower "false")
                 (= lower "off"))))

(fn ProfOutputPath.resolve [default-output-path]
  (local env (os.getenv "SPACE_FENNEL_FLAMEGRAPH"))
  (if (flamegraph-disabled? env)
      nil
      (if (use-default-output? env)
          default-output-path
          env)))

ProfOutputPath
