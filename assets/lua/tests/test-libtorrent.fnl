(local include-online (= (os.getenv "SPACE_LIBTORRENT_INCLUDE_ONLINE") "1"))

(fn collect-tests [module-name]
  (local suite (require module-name))
  (assert suite.tests (.. "module missing tests: " module-name))
  suite.tests)

(fn extend-tests [target source]
  (each [_ test (ipairs source)]
    (table.insert target test)))

(local tests [])
(extend-tests tests (collect-tests :tests.test-libtorrent-offline))

(when include-online
  (extend-tests tests (collect-tests :tests.test-libtorrent-online)))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name (if include-online
                                 "libtorrent-suite-offline+online"
                                 "libtorrent-suite-offline")
                       :tests tests})))

{:name "libtorrent"
 :tests tests
 :main main}
