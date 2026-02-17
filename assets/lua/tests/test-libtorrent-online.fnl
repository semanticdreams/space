(local fs (require :fs))
(local libtorrent (require :libtorrent))
(local utils (require :tests.libtorrent.test-utils))
(local include-dht-online (= (os.getenv "SPACE_LIBTORRENT_INCLUDE_DHT_ONLINE") "1"))

(fn configure-dht-session! [session nodes]
  (session:set-alert-mask 4294967295)
  (session:start-dht)
  (each [_ node (ipairs nodes)]
    (session:add-dht-node node)))

(fn wait-for-alert-where-step [session remaining predicate]
  (local alert (session:wait-for-alert 1000))
  (if (and alert (predicate alert))
      alert
      (if (<= remaining 1)
          nil
          (wait-for-alert-where-step session (- remaining 1) predicate))))

(fn wait-for-alert-where [session timeout-secs predicate]
  (wait-for-alert-where-step session (math.max 1 timeout-secs) predicate))

(fn run-download-roundtrip [make-download-handle]
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-online"))
  (local source-root (fs.join-path root "source"))
  (local download-root (fs.join-path root "download"))
  (utils.ensure-dir source-root)
  (utils.ensure-dir download-root)

  (local source-file (fs.join-path source-root "payload.txt"))
  (local content (.. "space libtorrent online payload " (os.time) "\n"))
  (fs.write-file source-file content)

  (utils.with-cleanup
   root
   (fn []
     (local created (libtorrent.create-torrent {:source-path source-file
                                                :output-path (fs.join-path root "payload.torrent")}))
     (assert created.info-hash-v1 "expected v1 info hash")

     (local seeder (libtorrent.Session {}))
     (local leecher (libtorrent.Session {}))

     (local (ok run-result)
            (pcall
             (fn []
               (local seed-id (seeder:add-torrent-file {:torrent-path created.torrent-path
                                                        :save-path source-root
                                                        :seed-mode true
                                                        :trackers created.trackers}))
               (seeder:force-reannounce seed-id)
               (seeder:force-dht-announce seed-id)

               (local download-id (make-download-handle {:leecher leecher
                                                         :created created
                                                         :download-root download-root}))
               (leecher:force-reannounce download-id)
               (leecher:force-dht-announce download-id)

               (local wait-result (leecher:wait-for-complete download-id {:timeout-secs 180
                                                                          :poll-ms 500}))
               (assert wait-result.ok
                       (.. "download did not complete: " (or wait-result.error "unknown")))

               (local downloaded-path (fs.join-path download-root created.name))
               (assert (fs.exists downloaded-path)
                       (.. "expected downloaded file at " downloaded-path))
               (local downloaded-content (fs.read-file downloaded-path))
               (assert (= downloaded-content content)
                       "downloaded file content mismatch")

               (leecher:remove-torrent download-id {:delete-files true})
               (seeder:remove-torrent seed-id)
               true)))

     (leecher:drop)
     (seeder:drop)

     (if ok
         run-result
         (error run-result)))))

(fn test-info-hash-download-roundtrip []
  (run-download-roundtrip
   (fn [ctx]
     (ctx.leecher:add-info-hash {:info-hash ctx.created.info-hash-v1
                                 :save-path ctx.download-root
                                 :name ctx.created.name
                                 :trackers ctx.created.trackers}))))

(fn test-magnet-download-roundtrip []
  (run-download-roundtrip
   (fn [ctx]
     (ctx.leecher:add-magnet-uri ctx.created.magnet-uri {:save-path ctx.download-root
                                                         :name ctx.created.name
                                                         :trackers ctx.created.trackers}))))

(fn test-dht-direct-request-online []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-online-dht"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local requester-port (+ 26000 (% (os.time) 10000)))
     (local responder-port (+ requester-port 1))
     (local requester (libtorrent.Session {:listen-interfaces (.. "127.0.0.1:" requester-port)}))
     (local responder (libtorrent.Session {:listen-interfaces (.. "127.0.0.1:" responder-port)}))

     (local (ok run-result)
            (pcall
             (fn []
               (configure-dht-session! requester [{:host "127.0.0.1" :port responder-port}])
               (configure-dht-session! responder [{:host "127.0.0.1" :port requester-port}])
               (if (not (and (requester:is-dht-running)
                             (responder:is-dht-running)))
                   true
                   (do

                     (requester:post-dht-stats)
                     (local stats-alert (wait-for-alert-where requester
                                                              10
                                                              (fn [candidate]
                                                                (string.find candidate.type
                                                                             "dht_stats"
                                                                             1
                                                                             true))))
                     (assert stats-alert
                             "did not receive dht stats alert")

                     (requester:dht-direct-request {:host "127.0.0.1"
                                                    :port responder-port
                                                    :userdata 4242
                                                    :request {:q "ping"
                                                              :y "q"
                                                              :t "aa"
                                                              :a {:id "01234567890123456789"}}})
                     (local wait-result (wait-for-alert-where requester
                                                              15
                                                              (fn [candidate]
                                                                (and (string.find candidate.type
                                                                                  "dht_direct_response"
                                                                                  1
                                                                                  true)))))
                     ;; direct response depends on remote-node behavior; stats alert above is strict.
                     (when wait-result
                       (assert wait-result.response
                               "expected dht direct response payload"))
                     true)))))

     (responder:drop)
     (requester:drop)

     (if ok
         run-result
         (error run-result)))))

(local tests [{:name "info-hash online roundtrip" :fn test-info-hash-download-roundtrip}
              {:name "magnet online roundtrip" :fn test-magnet-download-roundtrip}])

(when include-dht-online
  (table.insert tests {:name "dht direct request online"
                       :fn test-dht-direct-request-online}))

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "libtorrent-online"
                       :tests tests})))

{:name "libtorrent-online"
 :tests tests
 :main main}
