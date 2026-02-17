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

(fn default-data-root []
  (local xdg-data-home (os.getenv "XDG_DATA_HOME"))
  (if (and xdg-data-home (> (# xdg-data-home) 0))
      (fs.join-path xdg-data-home "space" "libtorrent" "uploads")
      (do
        (local home (os.getenv "HOME"))
        (assert (and home (> (# home) 0))
                "torrent-upload requires HOME or XDG_DATA_HOME to determine data path")
        (fs.join-path home ".local" "share" "space" "libtorrent" "uploads"))))

(fn djb2-hash-hex [text]
  (var h 5381)
  (for [i 1 (# text)]
    (set h (% (+ (* h 33) (string.byte text i)) 4294967296)))
  (string.format "%08x" h))

(fn parse-args [args]
  (local filtered [])
  (each [_ value (ipairs args)]
    (when (not (= value "--"))
      (tset filtered (+ (# filtered) 1) value)))
  (assert (= (# filtered) 1)
          "usage: ./build/space -m tools.torrent-upload:main -- <source-path>")
  (. filtered 1))

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

(fn collect-fingerprint-entries! [path out]
  (local stat (fs.stat path))
  (assert stat.exists (.. "source path does not exist: " path))
  (table.insert out (string.format "%s|%s|%s|%s|%s"
                                   stat.path
                                   stat.type
                                   (tostring (or stat.size 0))
                                   (tostring (or stat.modified 0))
                                   (or stat.permissions "")))
  (when stat.is-dir
    (local children (fs.list-dir path true))
    (table.sort children (fn [a b] (< a.path b.path)))
    (each [_ child (ipairs children)]
      (collect-fingerprint-entries! child.path out))))

(fn compute-source-fingerprint [absolute-path]
  (local entries [])
  (collect-fingerprint-entries! absolute-path entries)
  (djb2-hash-hex (table.concat entries "\n")))

(fn source-save-path [absolute-path]
  (local stat (fs.stat absolute-path))
  (assert stat.exists (.. "source path does not exist: " absolute-path))
  (if stat.is-dir
      (fs.parent absolute-path)
      (fs.parent absolute-path)))

(fn maybe-create-torrent! [absolute-path torrent-path force?]
  (if (or force? (not (file-exists? torrent-path)))
      (libtorrent.create-torrent {:source-path absolute-path
                                  :output-path torrent-path
                                  :creator "space/tools.torrent-upload"})
      (libtorrent.load-torrent-file torrent-path)))

(fn print-status [status]
  (local percent (* status.progress 100.0))
  (print (string.format "%s | %.2f%% | peers=%d seeds=%d | down=%d B/s up=%d B/s"
                        (or status.state "unknown")
                        percent
                        (or status.num-peers 0)
                        (or status.num-seeds 0)
                        (or status.download-rate 0)
                        (or status.upload-rate 0)))
  (when status.error
    (print (.. "torrent error: " status.error))))

(fn main []
  (assert libtorrent "libtorrent module missing")
  (assert libtorrent.available
          (.. "libtorrent unavailable: " (or (. libtorrent :missing-reason) "unknown")))

  (local source-input (parse-args _G.arg))
  (local absolute-source (fs.absolute source-input))
  (local source-stat (fs.stat absolute-source))
  (assert source-stat.exists (.. "source path does not exist: " absolute-source))
  (assert (or source-stat.is-dir source-stat.is-file)
          "source path must be a file or directory")

  (local source-id (djb2-hash-hex absolute-source))
  (local root (fs.join-path (default-data-root) source-id))
  (local state-path (fs.join-path root "state.json"))
  (local torrent-path (fs.join-path root "published.torrent"))
  (ensure-dir! root)

  (local fingerprint (compute-source-fingerprint absolute-source))
  (local existing (load-state state-path))
  (local changed? (or (not existing) (not= existing.source-fingerprint fingerprint)))
  (local published (maybe-create-torrent! absolute-source torrent-path changed?))
  (local save-path (source-save-path absolute-source))

  (local magnet-uri (or published.magnet-uri (libtorrent.make-magnet-uri torrent-path)))
  (local info-hash (or published.info-hash-v1
                       (and existing existing.info-hash)
                       (do
                         (local parsed (libtorrent.parse-magnet-uri magnet-uri))
                         parsed.info-hash)))
  (assert info-hash "failed to resolve info-hash for published torrent")

  (write-state! state-path {:source-path absolute-source
                            :source-kind (if source-stat.is-dir "directory" "file")
                            :source-fingerprint fingerprint
                            :torrent-path torrent-path
                            :info-hash (string.lower info-hash)
                            :magnet-uri magnet-uri
                            :save-path save-path
                            :updated-at (os.time)})

  (local session (libtorrent.Session {}))
  (session:start-dht)
  (local handle-id (session:add-torrent-file {:torrent-path torrent-path
                                              :save-path save-path
                                              :seed-mode true
                                              :trackers (or published.trackers nil)}))

  (print (.. "source-path: " absolute-source))
  (print (.. "save-path: " save-path))
  (print (.. "state-path: " state-path))
  (print (.. "torrent-path: " torrent-path))
  (print (.. "info-hash: " (string.lower info-hash)))
  (print (.. "magnet-uri: " magnet-uri))
  (if changed?
      (print "publish-state: source changed, regenerated torrent metadata")
      (print "publish-state: source unchanged, reused existing torrent metadata"))
  (print "running as seeder; press Ctrl-C to stop")

  (var last-printed-sec -1)
  (while true
    (session:wait-for-alert 250)
    (local now (os.time))
    (when (> now last-printed-sec)
      (set last-printed-sec now)
      (print-status (session:status handle-id)))))

{:main main}
