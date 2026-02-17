(local fs (require :fs))
(local libtorrent (require :libtorrent))
(local utils (require :tests.libtorrent.test-utils))

(fn test-module-is-available []
  (utils.assert-available)
  (assert (= (type (libtorrent.version)) "string"))
  (assert (> (# (libtorrent.version)) 0)))

(fn test-create-torrent-and-parse-magnet []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local source-file (fs.join-path root "asset.txt"))
     (local payload "libtorrent offline payload\n")
     (fs.write-file source-file payload)

     (local torrent-path (fs.join-path root "asset.torrent"))
     (local created (libtorrent.create-torrent {:source-path source-file
                                                :output-path torrent-path
                                                :creator "space-tests"}))

     (assert (fs.exists torrent-path))
     (assert (= created.torrent-path torrent-path))
     (assert (= created.name "asset.txt"))
     (assert (= created.total-size (# payload)))
     (assert (= (# created.info-hash-v1) 40))
     (assert (string.find created.magnet-uri "magnet:?" 1 true)
             "expected magnet uri")

     (local parsed (libtorrent.parse-magnet-uri created.magnet-uri))
     (assert (= parsed.info-hash created.info-hash-v1))
     (assert (= parsed.name created.name))
     (local parsed-dict (libtorrent.parse-magnet-uri-dict created.magnet-uri))
     (assert (= parsed-dict.info-hash created.info-hash-v1))

     (local from-file (libtorrent.make-magnet-uri torrent-path))
     (local parsed-file (libtorrent.parse-magnet-uri from-file))
     (assert (= parsed-file.info-hash created.info-hash-v1))

     (local loaded-file (libtorrent.load-torrent-file torrent-path))
     (assert (= loaded-file.name created.name))
     (assert (= loaded-file.info-hash-v1 created.info-hash-v1))
     (assert (= loaded-file.total-size created.total-size))
     (assert (string.find loaded-file.magnet-uri "magnet:?" 1 true))

     (local raw-torrent (fs.read-file torrent-path))
     (local loaded-buffer (libtorrent.load-torrent-buffer raw-torrent))
     (assert (= loaded-buffer.name created.name))
     (assert (= loaded-buffer.info-hash-v1 created.info-hash-v1))
     (assert (= loaded-buffer.total-size created.total-size)))))

(fn test-magnet-uri-from-params-handle []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local source-file (fs.join-path root "params-magnet-asset.txt"))
     (local payload "params magnet payload\n")
     (fs.write-file source-file payload)

     (local torrent-path (fs.join-path root "params-magnet-asset.torrent"))
     (local created (libtorrent.create-torrent {:source-path source-file
                                                :output-path torrent-path}))
     (local params (libtorrent.load-torrent-file-params torrent-path))
     (local magnet-uri (libtorrent.make-magnet-uri-from-params params))
     (assert (string.find magnet-uri "magnet:?" 1 true))
     (local parsed (libtorrent.parse-magnet-uri magnet-uri))
     (assert (= parsed.info-hash created.info-hash-v1))
     true)))

(fn test-bencode-bdecode-roundtrip []
  (utils.assert-available)
  (local payload {:announce "udp://tracker.example:6969/announce"
                  :info {:name "payload.txt"
                         :piece-length 16384
                         :length 5
                         :pieces "12345678901234567890"}
                  :announce-list [["udp://tracker.example:6969/announce"]
                                  ["udp://tracker.backup:6969/announce"]]})
  (local encoded (libtorrent.bencode payload))
  (assert (= (type encoded) "string"))
  (assert (> (# encoded) 0))
  (local decoded (libtorrent.bdecode encoded))
  (assert (= decoded.announce payload.announce))
  (assert (= decoded.info.name payload.info.name))
  (assert (= decoded.info.piece-length payload.info.piece-length))
  (assert (= decoded.info.length payload.info.length))
  (assert (= decoded.info.pieces payload.info.pieces))
  (assert (= (. (. (. decoded.announce-list 1) 1)) payload.announce))
  (assert (= (. (. (. decoded.announce-list 2) 1)) "udp://tracker.backup:6969/announce")))

(fn test-settings-presets []
  (utils.assert-available)
  (local default-settings (libtorrent.default-settings))
  (local seed-settings (libtorrent.high-performance-seed))
  (local memory-settings (libtorrent.min-memory-usage))

  (assert (= (type default-settings) "table"))
  (assert (= (type seed-settings) "table"))
  (assert (= (type memory-settings) "table"))
  (assert (= (type default-settings.enable-dht) "boolean"))
  (assert (= (type seed-settings.alert-mask) "number"))
  (assert (= (type memory-settings.connections-limit) "number"))
  (local torrent-flags (. libtorrent :torrent-flags))
  (assert (= (type torrent-flags.default-flags) "number"))
  (assert (= (type torrent-flags.paused) "number"))
  (assert (= (type torrent-flags.auto-managed) "number"))
  (local storage-modes (. libtorrent :storage-modes))
  (assert (= (type storage-modes.allocate) "number"))
  (assert (= (type storage-modes.sparse) "number")))

(fn test-session-stats-metrics-api []
  (utils.assert-available)
  (local metrics (libtorrent.session-stats-metrics))
  (assert (= (type metrics) "table"))
  (assert (> (# metrics) 0))
  (local first (. metrics 1))
  (assert (= (type first.name) "string"))
  (assert (= (type first.value-index) "number"))
  (local idx (libtorrent.find-metric-idx first.name))
  (assert (= idx first.value-index))
  (assert (= (libtorrent.find-metric-idx "space.metric.not-found") -1)))

(fn test-session-params-roundtrip []
  (utils.assert-available)
  (local base (libtorrent.session-params {}))
  (base:apply-settings {:user-agent "space-session-params/1.0"
                        :download-rate-limit 3456
                        :upload-rate-limit 6543
                        :connections-limit 42})
  (base:set-ext-state {:space "ok" :suite "libtorrent"})

  (local encoded-buf (libtorrent.write-session-params-buf base))
  (assert (= (type encoded-buf) "string"))
  (assert (> (# encoded-buf) 0))

  (local encoded-table (libtorrent.write-session-params base))
  (assert (= (type encoded-table) "table"))

  (local roundtrip (libtorrent.read-session-params encoded-buf))
  (local roundtrip-table (roundtrip:to-table))
  (assert (= roundtrip-table.settings.user-agent "space-session-params/1.0"))
  (assert (= roundtrip-table.settings.download-rate-limit 3456))
  (assert (= roundtrip-table.settings.upload-rate-limit 6543))
  (assert (= roundtrip-table.settings.connections-limit 42))
  (assert (= roundtrip-table.ext-state.space "ok"))
  (assert (= roundtrip-table.ext-state.suite "libtorrent"))

  (local ses (libtorrent.session {:session-params roundtrip}))
  (local ses-settings (ses:get-settings))
  (assert (= ses-settings.user-agent "space-session-params/1.0"))
  (assert (= ses-settings.download-rate-limit 3456))
  (assert (= ses-settings.upload-rate-limit 6543))
  (assert (= ses-settings.connections-limit 42))

  (local save-state-flags (. libtorrent :save-state-flags))
  (assert (= (type save-state-flags.save-settings) "number"))
  (assert (= (type save-state-flags.save-dht-state) "number"))
  (assert (= (type save-state-flags.save-extension-state) "number"))
  (assert (= (type save-state-flags.save-ip-filter) "number"))
  (assert (= (type save-state-flags.all) "number"))

  (local snapshot (ses:session-state save-state-flags.save-settings))
  (local snapshot-table (snapshot:to-table))
  (assert (= snapshot-table.settings.user-agent "space-session-params/1.0"))
  (ses:drop))

(fn test-ed25519-and-mutable-signing []
  (utils.assert-available)
  (local seed (libtorrent.ed25519-create-seed))
  (assert (= (# seed) 64))
  (local keypair (libtorrent.ed25519-create-keypair seed))
  (assert (= (# keypair.public-key) 64))
  (assert (= (# keypair.secret-key) 128))

  (local item {:name "mutable-item" :count 2})
  (local signature (libtorrent.sign-mutable-item {:item item
                                                  :public-key keypair.public-key
                                                  :secret-key keypair.secret-key
                                                  :salt "space"
                                                  :seq 1}))
  (assert (= (# signature) 128))
  (local (ok verify-result)
         (pcall (fn []
                  (libtorrent.verify-mutable-item {:item item
                                                   :public-key keypair.public-key
                                                   :signature signature
                                                   :salt "space"
                                                   :seq 1}))))
  (if ok
      (assert (= (type verify-result) "boolean"))
      (assert (string.find verify-result "verify-mutable-item unavailable" 1 true))))

(fn test-error-category-and-operation-name-apis []
  (utils.assert-available)
  (assert (= (type (libtorrent.operation-name 0)) "string"))
  (assert (> (# (libtorrent.operation-name 0)) 0))
  (assert (= (type (libtorrent.libtorrent-category-name)) "string"))
  (assert (= (type (libtorrent.http-category-name)) "string"))
  (assert (= (type (libtorrent.socks-category-name)) "string"))
  (assert (= (type (libtorrent.upnp-category-name)) "string"))
  (assert (= (type (libtorrent.i2p-category-name)) "string"))
  (assert (= (type (libtorrent.system-category-name)) "string"))
  (assert (= (type (libtorrent.generic-category-name)) "string"))
  (assert (= (type (libtorrent.bdecode-category-name)) "string")))

(fn test-session-lifecycle []
  (utils.assert-available)
  (local ses (libtorrent.session {:listen-interfaces "0.0.0.0:0,[::]:0"}))
  (assert ses)
  (assert (not (ses:is-closed)))
  (ses:drop)
  (assert (ses:is-closed)))

(fn test-session-settings-and-controls []
  (utils.assert-available)
  (local ses (libtorrent.session {}))

  (local before (ses:get-settings))
  (assert (= (type before.listen-interfaces) "string"))

  (ses:apply-settings {:user-agent "space-tests/1.0"
                       :download-rate-limit 11111
                       :upload-rate-limit 22222
                       :connections-limit 55
                       :enable-dht true
                       :announce-to-all-tiers true
                       :announce-to-all-trackers true})
  (local after (ses:get-settings))
  (assert (= after.user-agent "space-tests/1.0"))
  (assert (= after.download-rate-limit 11111))
  (assert (= after.upload-rate-limit 22222))
  (assert (= after.connections-limit 55))
  (assert (= after.enable-dht true))

  (ses:pause)
  (assert (ses:is-paused))
  (ses:resume)
  (assert (not (ses:is-paused)))

  (local dht-before (ses:is-dht-running))
  (assert (= (type dht-before) "boolean"))
  (ses:stop-dht)
  (ses:start-dht)
  (assert (= (type (ses:is-dht-running)) "boolean"))

  (ses:add-dht-node {:host "router.bittorrent.com" :port 6881})
  (local (router-ok router-err)
         (pcall (fn []
                  (ses:add-dht-router {:host "router.bittorrent.com" :port 6881}))))
  (when (not router-ok)
    (assert (string.find router-err "add-dht-router unavailable" 1 true)))

  (local fake-hash "0123456789abcdef0123456789abcdef01234567")
  (local dht-announce-flags (. libtorrent :dht-announce-flags))
  (assert (= (type dht-announce-flags.seed) "number"))
  (assert (= (type dht-announce-flags.implied-port) "number"))
  (assert (= (type dht-announce-flags.ssl-torrent) "number"))
  (ses:dht-get-peers fake-hash)
  (ses:dht-announce {:info-hash fake-hash
                     :port 0
                     :flags dht-announce-flags.implied-port})
  (ses:dht-live-nodes fake-hash)
  (ses:dht-sample-infohashes {:host "1.1.1.1"
                              :port 6881
                              :target fake-hash})
  (ses:dht-direct-request {:host "1.1.1.1"
                           :port 6881
                           :request {:q "ping"
                                     :y "q"
                                     :a {:id "01234567890123456789"}}})
  (local put-target (ses:dht-put-item {:space "dht-item"
                                       :kind "immutable"}))
  (assert (= (# put-target) 40))
  (ses:dht-get-item put-target)
  (local keypair (libtorrent.ed25519-create-keypair (libtorrent.ed25519-create-seed)))
  (ses:dht-put-mutable-item {:public-key keypair.public-key
                             :secret-key keypair.secret-key
                             :salt "space-mutable"
                             :seq 1
                             :item {:kind "mutable"
                                    :count 1}})
  (ses:dht-get-mutable-item {:public-key keypair.public-key
                             :salt "space-mutable"})

  (local status (ses:session-status))
  (assert (= (type status.download-rate) "number"))
  (assert (= (type status.upload-rate) "number"))
  (assert (= (type status.num-peers) "number"))
  (assert (= (type status.has-incoming-connections) "boolean"))

  (var saw-dht-alert false)
  (for [_ 1 20]
    (local next-alert (ses:wait-for-alert 50))
    (when (and next-alert
               (or next-alert.target
                   next-alert.public-key
                   next-alert.item
                   next-alert.num-peers
                   next-alert.num-nodes
                   next-alert.num-samples
                   next-alert.announce-info-hash
                   next-alert.response))
      (set saw-dht-alert true)
      (when next-alert.target
        (assert (= (type next-alert.target) "string")))
      (when next-alert.num-peers
        (assert (= (type next-alert.num-peers) "number")))
      (when next-alert.num-nodes
        (assert (= (type next-alert.num-nodes) "number")))
      (when next-alert.num-samples
        (assert (= (type next-alert.num-samples) "number")))
      (when next-alert.announce-info-hash
        (assert (= (type next-alert.announce-info-hash) "string")))
      (when next-alert.response
        (assert (= (type next-alert.endpoint-host) "string"))
        (assert (= (type next-alert.endpoint-port) "number")))))
  (assert (= (type saw-dht-alert) "boolean"))

  (ses:drop))

(fn test-session-alert-apis []
  (utils.assert-available)
  (local ses (libtorrent.session {}))
  (ses:set-alert-mask 4294967295)
  (local old-limit (ses:set-alert-queue-size-limit 2000))
  (assert (= (type old-limit) "number"))
  (ses:post-session-stats)
  (ses:post-dht-stats)
  (ses:post-torrent-updates)

  (var saw-alert false)
  (var saw-enriched false)
  (for [_ 1 20]
    (local next-alert (ses:wait-for-alert 100))
    (when next-alert
      (set saw-alert true)
      (when (or next-alert.counters-count
                next-alert.active-requests-count
                next-alert.status-count)
        (set saw-enriched true))))
  (assert saw-alert "expected at least one posted alert")

  (local maybe-alert (ses:wait-for-alert 10))
  (when maybe-alert
    (assert (= (type maybe-alert.type) "string"))
    (assert (= (type maybe-alert.message) "string"))
    (assert (= (type maybe-alert.category) "number"))
    (assert (= (type maybe-alert.alert-type) "number"))
    (assert (= (type maybe-alert.timestamp-ms) "number")))
  (local alerts (ses:pop-alerts))
  (assert (= (type alerts) "table"))
  (each [_ alert (ipairs alerts)]
    (assert (= (type alert.type) "string"))
    (assert (= (type alert.message) "string"))
    (assert (= (type alert.category) "number"))
    (assert (= (type alert.alert-type) "number"))
    (assert (= (type alert.timestamp-ms) "number"))
    (when alert.status-count
      (assert (= (type alert.status-count) "number")))
    (when alert.counters-count
      (assert (= (type alert.counters-count) "number")))
    (when alert.active-requests-count
      (assert (= (type alert.active-requests-count) "number")))
    (when alert.routing-table-count
      (assert (= (type alert.routing-table-count) "number")))
    (when alert.state
      (assert (= (type alert.state) "string")))
    (when alert.prev-state
      (assert (= (type alert.prev-state) "string"))))
  (ses:drop))

(fn test-add-info-hash-and-timeout []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local ses (libtorrent.session {}))
     (local info-hash "0123456789abcdef0123456789abcdef01234567")
     (local handle-id (ses:add-info-hash {:info-hash info-hash
                                          :save-path root
                                          :name "offline-timeout-check"}))
     (assert (> handle-id 0))

     (local wait-result (ses:wait-for-complete handle-id {:timeout-secs 1 :poll-ms 50}))
     (assert (= (type wait-result.ok) "boolean"))
     (assert (= (type wait-result.timeout) "boolean"))
     (assert wait-result.status)

     (ses:remove-torrent handle-id)
     (ses:drop)
     true)))

(fn test-add-torrent-file-validation []
  (utils.assert-available)
  (local ses (libtorrent.session {}))

  (local (ok-1 err-1) (pcall (fn []
                               (ses:add-torrent-file {:save-path "/tmp"}))))
  (assert (not ok-1))
  (assert (string.find err-1 "requires torrent-path" 1 true))

  (local (ok-2 err-2) (pcall (fn []
                               (ses:add-torrent-file {:torrent-path "/tmp/nope.torrent"}))))
  (assert (not ok-2))
  (assert (string.find err-2 "requires save-path" 1 true))

  (ses:drop))

(fn test-add-torrent-params-and-resume-roundtrip []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local source-file (fs.join-path root "params-asset.txt"))
     (local payload "libtorrent params payload\n")
     (fs.write-file source-file payload)

     (local torrent-path (fs.join-path root "params-asset.torrent"))
     (local created (libtorrent.create-torrent {:source-path source-file
                                                :output-path torrent-path}))

     (local params (libtorrent.load-torrent-file-params torrent-path))
     (params:set-save-path root)
     (params:set-name "params-asset")
     (params:set-trackers created.trackers)
     (params:set-upload-limit 1234)
     (params:set-download-limit 5678)
     (params:set-max-connections 12)
     (params:set-max-uploads 34)
     (local storage-modes (. libtorrent :storage-modes))
     (params:set-storage-mode storage-modes.allocate)
     (params:set-tracker-tiers [0 1 1 2])
     (params:set-url-seeds ["https://seed-a.example" "https://seed-b.example"])
     (params:set-dht-nodes [{:host "router.bittorrent.com" :port 6881}
                            {:host "router.utorrent.com" :port 6881}])
     (params:set-file-priorities [7 2 0])
     (params:set-piece-priorities [1 4 7])

     (local start-flags (params:get-flags))
     (assert (= (type start-flags) "number"))
     (local torrent-flags (. libtorrent :torrent-flags))
     (params:or-flags torrent-flags.sequential-download)
     (local with-seq (params:get-flags))
     (assert (not (= with-seq start-flags)))
     (params:clear-flags torrent-flags.sequential-download)
     (local without-seq (params:get-flags))
     (assert (= without-seq start-flags))
     (params:set-flags torrent-flags.default-flags)

     (local params-table (params:to-table))
     (assert (= params-table.save-path root))
     (assert (= params-table.name "params-asset"))
     (assert (= params-table.info-hash-v1 created.info-hash-v1))
     (assert (= params-table.upload-limit 1234))
     (assert (= params-table.download-limit 5678))
     (assert (= params-table.max-connections 12))
     (assert (= params-table.max-uploads 34))
     (assert (= params-table.storage-mode storage-modes.allocate))
     (assert (= params-table.flags torrent-flags.default-flags))
     (assert (= (# params-table.tracker-tiers) 4))
     (assert (= (. params-table.tracker-tiers 4) 2))
     (assert (= (# params-table.url-seeds) 2))
     (assert (= (. params-table.url-seeds 1) "https://seed-a.example"))
     (assert (= (# params-table.dht-nodes) 2))
     (assert (= (. (. params-table.dht-nodes 1) :port) 6881))
     (assert (= (# params-table.file-priorities) 3))
     (assert (= (. params-table.file-priorities 1) 7))
     (assert (= (# params-table.piece-priorities) 3))
     (assert (= (. params-table.piece-priorities 3) 7))

     (local torrent-buffer (params:write-torrent-file-buf))
     (assert (> (# torrent-buffer) 0))
     (local parsed-buffer (libtorrent.load-torrent-buffer-params torrent-buffer))
     (local parsed-table (parsed-buffer:to-table))
     (assert (= parsed-table.info-hash-v1 created.info-hash-v1))

     (local resume-buffer (params:write-resume-data-buf))
     (assert (> (# resume-buffer) 0))
     (local resume-buffer-top (libtorrent.write-resume-data-buf params))
     (assert (> (# resume-buffer-top) 0))
     (local resume-table-top (libtorrent.write-resume-data params))
     (assert (= (type resume-table-top) "table"))
     (local resume-params (libtorrent.read-resume-data-params resume-buffer))
     (local resume-table (resume-params:to-table))
     (assert (= resume-table.info-hash-v1 created.info-hash-v1))
     (local resume-params-top (libtorrent.read-resume-data resume-buffer-top))
     (local resume-top-table (resume-params-top:to-table))
     (assert (= resume-top-table.info-hash-v1 created.info-hash-v1))

     (local ses (libtorrent.session {}))
     (local handle-id (ses:add-torrent-params {:params params
                                               :save-path root}))
     (assert (> handle-id 0))
     (local magnet-uri (ses:make-magnet-uri handle-id))
     (assert (string.find magnet-uri "magnet:?" 1 true))
     (local parsed-handle-magnet (libtorrent.parse-magnet-uri magnet-uri))
     (assert (= parsed-handle-magnet.info-hash created.info-hash-v1))
     (ses:remove-torrent handle-id)
     (ses:drop)
     true)))

(fn test-load-torrent-parsed-and-write-torrent-file []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local source-file (fs.join-path root "parsed-asset.txt"))
     (fs.write-file source-file "parsed payload\n")
     (local torrent-path (fs.join-path root "parsed-asset.torrent"))
     (local created (libtorrent.create-torrent {:source-path source-file
                                                :output-path torrent-path}))

     (local parsed (libtorrent.bdecode (fs.read-file torrent-path)))
     (local params (libtorrent.load-torrent-parsed parsed))
     (local params-table (params:to-table))
     (assert (= params-table.info-hash-v1 created.info-hash-v1))

     (local encoded-buf (libtorrent.write-torrent-file-buf params))
     (assert (> (# encoded-buf) 0))
     (local loaded (libtorrent.load-torrent-buffer encoded-buf))
     (assert (= loaded.info-hash-v1 created.info-hash-v1))

     (local encoded-table (libtorrent.write-torrent-file params))
     (assert (= encoded-table.info.name created.name))
     true)))

(fn test-add-torrent-params-duplicate-is-error []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local source-file (fs.join-path root "duplicate-asset.txt"))
     (fs.write-file source-file "duplicate params payload\n")
     (local torrent-path (fs.join-path root "duplicate-asset.torrent"))
     (libtorrent.create-torrent {:source-path source-file
                                 :output-path torrent-path})

     (local params (libtorrent.load-torrent-file-params torrent-path))
     (local torrent-flags (. libtorrent :torrent-flags))
     (params:or-flags torrent-flags.duplicate-is-error)

     (local ses (libtorrent.session {}))
     (local first-id (ses:add-torrent-params {:params params
                                              :save-path root}))
     (assert (> first-id 0))

     (local (ok err) (pcall (fn []
                              (ses:add-torrent-params {:params params
                                                       :save-path root}))))
     (assert (not ok))
     (assert (string.find err "add-torrent-params failed" 1 true))

     (ses:remove-torrent first-id)
     (ses:drop)
     true)))

(fn test-session-find-and-list-torrents []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local source-file (fs.join-path root "find-list-asset.txt"))
     (fs.write-file source-file "find-list payload\n")

     (local torrent-path (fs.join-path root "find-list-asset.torrent"))
     (local created (libtorrent.create-torrent {:source-path source-file
                                                :output-path torrent-path}))

     (local ses (libtorrent.session {}))
     (local handle-id (ses:add-torrent-file {:torrent-path torrent-path
                                             :save-path root
                                             :seed-mode true}))
     (assert (> handle-id 0))

     (local torrents (ses:get-torrents))
     (assert (> (# torrents) 0))
     (var found-by-list false)
     (each [_ item (ipairs torrents)]
       (when (= item.info-hash-v1 created.info-hash-v1)
         (set found-by-list true)
         (assert (= item.handle-id handle-id))
         (assert (= (type item.name) "string"))
         (assert (= (type item.is-valid) "boolean"))))
     (assert found-by-list "expected torrent in get-torrents list")

     (local found-id (ses:find-torrent created.info-hash-v1))
     (assert (= found-id handle-id))

     (ses:remove-torrent handle-id)
     (local after-remove (ses:find-torrent created.info-hash-v1))
     (assert (= after-remove nil))

     (ses:drop)
     true)))

(fn test-torrent-handle-controls []
  (utils.assert-available)
  (local root (utils.make-root "libtorrent-offline"))
  (utils.ensure-dir root)

  (utils.with-cleanup
   root
   (fn []
     (local source-file (fs.join-path root "controls-asset.txt"))
     (fs.write-file source-file "controls payload\n")
     (local torrent-path (fs.join-path root "controls-asset.torrent"))
     (local created (libtorrent.create-torrent {:source-path source-file
                                                :output-path torrent-path}))
     (local download-root (fs.join-path root "controls-download"))
     (fs.create-dirs download-root)

     (local ses (libtorrent.session {}))
     (local handle-id (ses:add-torrent-file {:torrent-path torrent-path
                                             :save-path download-root}))
     (assert (> handle-id 0))

     (ses:set-torrent-download-limit handle-id 13579)
     (ses:set-torrent-upload-limit handle-id 97531)
     (ses:set-torrent-max-connections handle-id 22)
     (ses:set-torrent-max-uploads handle-id 11)
     (assert (= (ses:torrent-download-limit handle-id) 13579))
     (assert (= (ses:torrent-upload-limit handle-id) 97531))
     (assert (= (ses:torrent-max-connections handle-id) 22))
     (assert (= (ses:torrent-max-uploads handle-id) 11))

     (ses:set-torrent-piece-priorities handle-id [7])
     (local piece-priorities (ses:torrent-piece-priorities handle-id))
     (assert (= (# piece-priorities) 1))
     (assert (= (. piece-priorities 1) 7))

     (ses:set-torrent-file-priorities handle-id [5])
     (var file-priorities nil)
     (var file-priority-applied false)
     (for [_ 1 20]
       (set file-priorities (ses:torrent-file-priorities handle-id))
       (when (and (= (# file-priorities) 1)
                  (= (. file-priorities 1) 5))
         (set file-priority-applied true))
       (when (not file-priority-applied)
         (ses:wait-for-alert 50)))
     (assert file-priority-applied "expected file priority update to apply")

     (ses:pause-torrent handle-id)
     (ses:resume-torrent handle-id)

     (local info (ses:torrent-info handle-id))
     (assert (= info.handle-id handle-id))
     (assert (= info.info-hash-v1 created.info-hash-v1))
     (assert (= info.download-limit 13579))
     (assert (= info.upload-limit 97531))
     (assert (= info.max-connections 22))
     (assert (= info.max-uploads 11))
     (assert (= (type info.name) "string"))

     (ses:remove-torrent handle-id)
     (ses:drop)
     true)))

(local tests [{:name "module availability" :fn test-module-is-available}
              {:name "create torrent and parse magnet" :fn test-create-torrent-and-parse-magnet}
              {:name "settings presets" :fn test-settings-presets}
              {:name "bencode bdecode roundtrip" :fn test-bencode-bdecode-roundtrip}
              {:name "session stats metrics api" :fn test-session-stats-metrics-api}
              {:name "session params roundtrip" :fn test-session-params-roundtrip}
              {:name "ed25519 and mutable signing" :fn test-ed25519-and-mutable-signing}
              {:name "error category and operation name apis" :fn test-error-category-and-operation-name-apis}
              {:name "session lifecycle" :fn test-session-lifecycle}
              {:name "session settings and controls" :fn test-session-settings-and-controls}
              {:name "session alert apis" :fn test-session-alert-apis}
              {:name "add info-hash and timeout" :fn test-add-info-hash-and-timeout}
              {:name "add-torrent-file validation" :fn test-add-torrent-file-validation}
              {:name "magnet uri from params handle" :fn test-magnet-uri-from-params-handle}
              {:name "add-torrent-params and resume roundtrip" :fn test-add-torrent-params-and-resume-roundtrip}
              {:name "load-torrent-parsed and write-torrent-file" :fn test-load-torrent-parsed-and-write-torrent-file}
              {:name "add-torrent-params duplicate is error" :fn test-add-torrent-params-duplicate-is-error}
              {:name "session find and list torrents" :fn test-session-find-and-list-torrents}
              {:name "torrent handle controls" :fn test-torrent-handle-controls}])

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "libtorrent-offline"
                       :tests tests})))

{:name "libtorrent-offline"
 :tests tests
 :main main}
