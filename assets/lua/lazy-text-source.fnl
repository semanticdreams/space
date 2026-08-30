(local fs (require :fs))

(fn resolve-chunk-bytes [opts]
  (if (and opts (not= opts.chunk-bytes nil))
      opts.chunk-bytes
      65536))

(fn file [path opts]
  (local absolute-path (fs.absolute path))
  (local token (fs.file-token absolute-path))
  (local read-range
    (fn [_self offset max-bytes]
      (fs.read-byte-range absolute-path offset max-bytes)))
  (local current-token
    (fn [_self]
      (fs.file-token absolute-path)))
  (local refresh-token
    (fn [source]
      (local next-token (source:current-token))
      (set source.baseline-token next-token)
      (set source.size next-token.size)
      next-token))
  {:path absolute-path
   :baseline-token token
   :size token.size
   :chunk-bytes (resolve-chunk-bytes opts)
   :read-range read-range
   :current-token current-token
   :refresh-token refresh-token})

{:file file}
