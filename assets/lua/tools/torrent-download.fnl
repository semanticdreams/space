(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local libtorrent (require :libtorrent))

(fn ensure-dir! [path]
  (when (not (fs.exists path))
    (fs.create-dirs path))
  path)

(fn file-exists? [path]
  (if (not path)
      false
      (do
        (local (ok exists?) (pcall fs.exists path))
        (if ok exists? false))))

(fn strip-btih-prefix [value]
  (if (string.find value "urn:btih:" 1 true)
      (string.sub value 10)
      value))

(fn is-hex-info-hash? [value]
  (and value (not= (string.match value "^[0-9A-Fa-f]+$") nil) (= (# value) 40)))

(fn default-data-root []
  (local xdg-data-home (os.getenv "XDG_DATA_HOME"))
  (if (and xdg-data-home (> (# xdg-data-home) 0))
      (fs.join-path xdg-data-home "space" "libtorrent")
      (do
        (local home (os.getenv "HOME"))
        (assert (and home (> (# home) 0))
                "torrent-download requires HOME or XDG_DATA_HOME to determine data path")
        (fs.join-path home ".local" "share" "space" "libtorrent"))))

(fn load-state [path]
  (if (file-exists? path)
      (do
        (local raw (fs.read-file path))
        (local (ok parsed) (pcall json.loads raw))
        (if ok
            parsed
            (error (.. "failed to parse state file " path ": " parsed))))
      nil))

(fn write-state! [path payload]
  (local parent (fs.parent path))
  (when parent
    (ensure-dir! parent))
  (JsonUtils.write-json! path payload))

(fn info-hash-from-torrent [torrent-path]
  (local loaded (libtorrent.load-torrent-file torrent-path))
  (assert loaded.info-hash-v1 "torrent file must contain v1 info hash")
  {:info-hash (string.lower loaded.info-hash-v1)
   :name loaded.name
   :magnet-uri loaded.magnet-uri})

(fn info-hash-from-magnet [uri]
  (local parsed (libtorrent.parse-magnet-uri uri))
  (assert parsed.info-hash "magnet uri must include a v1 btih info hash")
  {:info-hash (string.lower parsed.info-hash)
   :name parsed.name
   :magnet-uri uri})

(fn resolve-input [raw]
  (local maybe-hash (strip-btih-prefix raw))
  (if (string.find raw "magnet:?" 1 true)
      (do
        (local meta (info-hash-from-magnet raw))
        {:kind "magnet-uri"
         :info-hash meta.info-hash
         :name meta.name
         :magnet-uri raw})
      (if (is-hex-info-hash? maybe-hash)
          (do
            {:kind "info-hash"
             :info-hash (string.lower maybe-hash)
             :name nil
             :magnet-uri nil})
          (if (file-exists? raw)
              (do
                (local absolute-path (fs.absolute raw))
                (local meta (info-hash-from-torrent absolute-path))
                {:kind "torrent-file"
                 :info-hash meta.info-hash
                 :name meta.name
                 :magnet-uri meta.magnet-uri
                 :torrent-path absolute-path})
              (error "argument must be a valid .torrent file path, magnet URI, or 40-char hex info hash")))))

(fn maybe-copy-torrent! [from-path to-path]
  (when (and from-path (not= from-path to-path))
    (local parent (fs.parent to-path))
    (when parent
      (ensure-dir! parent))
    (fs.write-file to-path (fs.read-file from-path))))

(fn resolve-run-config [input]
  (local base-root (default-data-root))
  (local torrent-root (fs.join-path base-root input.info-hash))
  (local data-path (fs.join-path torrent-root "data"))
  (local state-path (fs.join-path torrent-root "state.json"))
  (local torrent-copy-path (fs.join-path torrent-root "source.torrent"))
  (ensure-dir! data-path)

  (local existing (load-state state-path))
  (when (and existing existing.info-hash (not= (string.lower existing.info-hash) input.info-hash))
    (error (.. "state info hash mismatch for " state-path)))

  (local chosen-name (or input.name (and existing existing.name) input.info-hash))
  (local chosen-magnet (or input.magnet-uri (and existing existing.magnet-uri)))
  (var chosen-torrent-path nil)
  (if input.torrent-path
      (do
        (maybe-copy-torrent! input.torrent-path torrent-copy-path)
        (set chosen-torrent-path torrent-copy-path))
      (when (file-exists? torrent-copy-path)
        (set chosen-torrent-path torrent-copy-path)))

  (write-state! state-path {:info-hash input.info-hash
                            :name chosen-name
                            :kind input.kind
                            :magnet-uri chosen-magnet
                            :torrent-path chosen-torrent-path
                            :data-path data-path
                            :updated-at (os.time)})

  {:info-hash input.info-hash
   :name chosen-name
   :data-path data-path
   :state-path state-path
   :magnet-uri chosen-magnet
   :torrent-path chosen-torrent-path})

(fn add-torrent! [session config]
  (if config.torrent-path
      (session:add-torrent-file {:torrent-path config.torrent-path
                                 :save-path config.data-path})
      (if config.magnet-uri
          (session:add-magnet-uri config.magnet-uri {:save-path config.data-path
                                                     :name config.name})
          (session:add-info-hash {:info-hash config.info-hash
                                  :save-path config.data-path
                                  :name config.name}))))

(fn format-rate [bytes-per-second]
  (if (>= bytes-per-second 1048576)
      (string.format "%.2f MiB/s" (/ bytes-per-second 1048576))
      (if (>= bytes-per-second 1024)
          (string.format "%.2f KiB/s" (/ bytes-per-second 1024))
          (string.format "%d B/s" bytes-per-second))))

(fn print-status [status]
  (local percent (* status.progress 100.0))
  (local down (format-rate (or status.download-rate 0)))
  (local up (format-rate (or status.upload-rate 0)))
  (local total (or status.total 0))
  (local done (or status.total-done 0))
  (local remaining (if (> total done) (- total done) 0))
  (print (string.format "%s | %.2f%% | peers=%d seeds=%d | down=%s up=%s"
                        (or status.state "unknown")
                        percent
                        (or status.num-peers 0)
                        (or status.num-seeds 0)
                        down
                        up))
  (when (> total 0)
    (print (string.format "done=%d / %d bytes (remaining=%d)"
                          done
                          total
                          remaining)))
  (when status.error
    (print (.. "torrent error: " status.error))))

(fn parse-args [args]
  (local filtered [])
  (each [idx value (ipairs args)]
    (when (not (= value "--"))
      (tset filtered (+ (# filtered) 1) value)))
  (assert (= (# filtered) 1)
          "usage: ./build/space -m tools.torrent-download:main -- <magnet|info-hash|torrent-file>")
  (. filtered 1))

(fn main []
  (assert libtorrent "libtorrent module missing")
  (assert libtorrent.available
          (.. "libtorrent unavailable: " (or (. libtorrent :missing-reason) "unknown")))

  (local raw-input (parse-args _G.arg))
  (local input (resolve-input raw-input))
  (local config (resolve-run-config input))

  (local session (libtorrent.Session {}))
  (session:start-dht)

  (local handle-id (add-torrent! session config))
  (local added-magnet (session:make-magnet-uri handle-id))
  (write-state! config.state-path {:info-hash config.info-hash
                                   :name config.name
                                   :kind input.kind
                                   :magnet-uri added-magnet
                                   :torrent-path config.torrent-path
                                   :data-path config.data-path
                                   :updated-at (os.time)})

  (print (.. "info-hash: " config.info-hash))
  (print (.. "data-path: " config.data-path))
  (print (.. "state-path: " config.state-path))
  (print "running; press Ctrl-C to stop (torrent will resume on next run)")

  (var last-printed-sec -1)
  (var best-progress 0.0)
  (var last-progress-sec (os.time))
  (var last-reannounce-sec 0)
  (local stall-reannounce-interval-secs 30)
  (local stall-threshold-secs 45)

  (while true
    (session:wait-for-alert 250)
    (local now (os.time))
    (when (> now last-printed-sec)
      (set last-printed-sec now)
      (local status (session:status handle-id))
      (when (> (or status.progress 0.0) best-progress)
        (set best-progress status.progress)
        (set last-progress-sec now))

      (local stalled-secs (- now last-progress-sec))
      (local near-complete (>= (or status.progress 0.0) 0.99))
      (local inactive-rate (<= (or status.download-rate 0) 0))
      (local no-useful-peers (<= (+ (or status.num-peers 0) (or status.num-seeds 0)) 0))
      (when (and near-complete
                 inactive-rate
                 no-useful-peers
                 (>= stalled-secs stall-threshold-secs)
                 (>= (- now last-reannounce-sec) stall-reannounce-interval-secs))
        (session:force-reannounce handle-id)
        (session:force-dht-announce handle-id)
        (set last-reannounce-sec now)
        (print (string.format "stalled for %ds near completion; forced reannounce + dht announce"
                              stalled-secs)))
      (print-status status))))

{:main main}
