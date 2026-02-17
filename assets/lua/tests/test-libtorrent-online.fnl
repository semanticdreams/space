(local fs (require :fs))
(local libtorrent (require :libtorrent))
(local utils (require :tests.libtorrent.test-utils))

(fn test-info-hash-download-roundtrip []
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

               (local download-id (leecher:add-info-hash {:info-hash created.info-hash-v1
                                                          :save-path download-root
                                                          :name created.name
                                                          :trackers created.trackers}))
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

(local tests [{:name "info-hash online roundtrip" :fn test-info-hash-download-roundtrip}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "libtorrent-online"
                       :tests tests})))

{:name "libtorrent-online"
 :tests tests
 :main main}
