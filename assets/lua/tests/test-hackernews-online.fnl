(local HackerNews (require :hackernews))
(local fs (require :fs))
(local appdirs (require :appdirs))

(var client nil)
(var sample-story-id nil)
(var sample-item nil)

(fn ensure-client []
  (when (not client)
    (assert app "app table must be present")
    (assert fs "fs module must be available")
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

    (local default-app-dir (app.get-app-dir "hackernews"))
    (assert (and fs.exists (fs.exists default-app-dir)) "app.get-app-dir should create hackernews directory")

    (local test-app-name "hackernews-tests")
    (local test-app-dir (app.get-app-dir test-app-name))
    (when (and fs fs.exists (fs.exists test-app-dir))
      (when (and fs fs.remove-all)
        (fs.remove-all test-app-dir)))
    (when (and fs fs.create-dirs)
      (fs.create-dirs test-app-dir))

    (set client (HackerNews {:requests_per_window 4
                             :window_ms 1000
                             :app-name test-app-name}))))

(fn await [future]
  (ensure-client)
  (client.wait future 30))

(fn test-topstories []
  (ensure-client)
  (local future (client.fetch-topstories))
  (local result (await future))
  (assert (> (# result) 0) "topstories should return at least one id")
  (set sample-story-id (. result 1))
  (local cached-future (client.fetch-topstories))
  (await cached-future)
  (assert (= (cached-future.source) "cache") "topstories should use cache on subsequent call")
  (assert (> (client.callback-count) 0) "callbacks should fire for topstories"))

(fn test-item []
  (ensure-client)
  (assert sample-story-id "sample story id missing")
  (local first-future (client.fetch-item sample-story-id))
  (local item (await first-future))
  (set sample-item item)
  (assert (= (first-future.source) "network") "initial item fetch should hit network")
  (assert (= item.id sample-story-id) "item id should match request")
  (assert item.title "item should include a title")
  (local second (client.fetch-item sample-story-id))
  (local cached-item (await second))
  (assert (= (second.source) "cache") "item should be served from cache on second fetch")
  (assert (= cached-item.id sample-story-id) "cached item should match id")
  (local cache-path (fs.join-path (client.cache-dir) (.. "item-" sample-story-id ".json")))
  (assert (fs.exists cache-path) "item cache file should exist"))

(fn test-user []
  (ensure-client)
  (local username (or (and sample-item sample-item.by) "pg"))
  (local future (client.fetch-user username))
  (local user (await future))
  (assert (or (= (future.source) "network")
              (= (future.source) "cache")) "user fetch should succeed")
  (assert (= user.id username) "user id should match request"))

(fn test-updates []
  (ensure-client)
  (local updates (await (client.fetch-updates)))
  (assert updates.items "updates should include item ids")
  (assert updates.profiles "updates should include profiles list"))

(fn test-max-item []
  (ensure-client)
  (local maxid (await (client.fetch-max-item)))
  (assert (and maxid (> maxid 0)) "max item id should be positive"))

(local tests [{:name "topstories" :fn test-topstories}
              {:name "item fetch and cache" :fn test-item}
              {:name "user fetch" :fn test-user}
              {:name "updates" :fn test-updates}
              {:name "max item" :fn test-max-item}])

(fn teardown []
  (when client
    (client.drop)))

(local main
     (fn []
       (local runner (require :tests/runner))
       (runner.run-tests {:name "hackernews-online"
                          :tests tests
                          :teardown teardown})))

{:name "hackernews-online"
 :tests tests
 :main main}
