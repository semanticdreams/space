(local HackerNews (require :hackernews))
(local fixtures (require :tests/http-fixtures))

(local fs (require :fs))
(local appdirs (require :appdirs))

(assert app.engine "engine table must be present")
(assert fs "fs module must be available")

(fn ensure-get-app-dir []
  (when (not app.get-app-dir)
    (assert appdirs "appdirs module must be present")
    (local data-dir (appdirs.user-data-dir "space"))
    (local apps-dir (fs.join-path data-dir "apps"))
    (when (and fs fs.create-dirs)
      (fs.create-dirs apps-dir))
    (set app.get-app-dir
         (fn [name]
           (assert name "app.get-app-dir requires a name")
           (local target (fs.join-path apps-dir name))
           (when (and fs fs.create-dirs)
             (fs.create-dirs target))
           target))))

(assert app.engine.get-asset-path "app.engine.get-asset-path must be available")

(local fixture-path (app.engine.get-asset-path "lua/tests/data/hackernews-fixture.json"))
(local fixture (fixtures.read-json fixture-path))

(fn find-request [requests key]
  (var found nil)
  (each [_ req (ipairs requests)]
    (when (= req.key key)
      (set found req)))
  found)

(fn with-client [cb]
  (ensure-get-app-dir)
  (var install nil)
  (var client nil)
  (local app-name "hackernews-offline-tests")
  (local app-dir (app.get-app-dir app-name))
  (when (and fs fs.exists (fs.exists app-dir))
    (when (and fs fs.remove-all)
      (fs.remove-all app-dir)))
  (when (and fs fs.create-dirs)
    (fs.create-dirs app-dir))
  (let [(ok result)
        (pcall
         (fn []
           (set install (fixtures.install-mock fixture))
           (set client (HackerNews {:requests_per_window 10
                                                   :window_ms 100
                                                   :app-name app-name}))
           (cb client install.mock)))]
    (when client
      (client.drop))
    (when install
      (install.restore))
    (when (and fs fs.exists (fs.exists app-dir))
      (when (and fs fs.remove-all)
        (fs.remove-all app-dir)))
    (if ok
        result
        (error result))))

(fn test-topstories-from-fixture []
  (with-client
   (fn [client mock]
     (local wait (fn [future] (client.wait future 2)))
     (local ids (wait (client.fetch-topstories)))
     (assert (= (. ids 1) 8863) "topstories fixture should include story id 8863")
     (assert (> (client.callback-count) 0) "mocked callback should still be invoked")
     (local req (find-request (mock.requests) "topstories"))
     (assert req "topstories request should be recorded")
     (assert (= req.status 200) "status should be preserved from fixture")
     (local header (and req.headers (. req.headers 1)))
     (assert header "headers should be captured")
     (assert (= (. header 1) "content-type") "content-type header should be present")
     (assert (string.find (. header 2) "json" 1 true) "content-type should mention json"))))

(fn test-item-cache-behavior []
  (with-client
   (fn [client mock]
     (local wait (fn [future] (client.wait future 2)))
     (local first (client.fetch-item 8863))
     (local item (wait first))
     (assert (= (first.source) "network") "first fetch should hit mocked network")
     (assert (= item.id 8863) "item id should round-trip through fixture")
     (local cache-path (fs.join-path (client.cache-dir) "item-8863.json"))
     (assert (fs.exists cache-path) "client should write cache file from mocked response")
     (local second (client.fetch-item 8863))
     (local cached (wait second))
     (assert (= (second.source) "cache") "second fetch should serve cached copy")
     (assert (= cached.title item.title) "cached item should match fixture payload")
     (local req (find-request (mock.requests) "item/8863"))
     (assert req "item request should be captured")
     (assert (= req.status 200) "item status should match fixture")
     (local header (and req.headers (. req.headers 1)))
     (assert header "item headers should be preserved")
     (assert (= (. header 1) "content-type")))))

(fn test-user-updates-and-max []
  (with-client
   (fn [client mock]
     (local wait (fn [future] (client.wait future 2)))
     (local user (wait (client.fetch-user "dhouston")))
     (assert (= user.id "dhouston") "user id should come from fixture")
     (local updates (wait (client.fetch-updates)))
     (assert (= (. updates.items 1) 8863) "updates should echo fixture items")
     (assert (= (. updates.profiles 1) "dhouston") "updates should include fixture profiles")
     (local maxid (wait (client.fetch-max-item)))
     (assert (= maxid 40000000) "maxitem should parse numeric body")
     (local requests (mock.requests))
     (local user-req (find-request requests "user/dhouston"))
     (assert user-req "user request should be recorded")
     (assert (= user-req.status 200))
     (local updates-req (find-request requests "updates"))
     (assert updates-req "updates request should be recorded")
     (assert (= updates-req.status 200))
     (local max-req (find-request requests "maxitem"))
     (assert max-req "maxitem request should be recorded")
     (local header (and max-req.headers (. max-req.headers 1)))
     (assert header "maxitem headers should be captured")
     (assert (= (. header 1) "content-type")))))

(local tests [{ :name "hackernews topstories uses fixture and headers" :fn test-topstories-from-fixture}
 { :name "hackernews item fetch writes cache with fixture" :fn test-item-cache-behavior}
 { :name "hackernews user updates and maxitem use fixture" :fn test-user-updates-and-max}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "hackernews-offline"
                       :tests tests})))

{:name "hackernews-offline"
 :tests tests
 :main main}
