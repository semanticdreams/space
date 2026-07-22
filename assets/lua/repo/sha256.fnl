(local Process (require :process))

(fn hash [content]
  (assert (= (type content) "string") "sha256 requires a string")
  (local result (Process.run {:args ["sha256sum"]
                              :stdin content
                              :merge-stderr true}))
  (assert (not result.timed-out) "sha256sum timed out")
  (assert (not result.signal) (.. "sha256sum signal: " (tostring result.signal)))
  (assert (= result.exit-code 0) (.. "sha256sum failed: " (or result.stderr result.stdout)))
  (local hex (string.match (or result.stdout "") "([%x]+)"))
  (assert hex (.. "sha256sum produced no hex output: " (tostring result.stdout)))
  hex)

(fn hash-file [path]
  (local fs (require :fs))
  (hash (fs.read-file path)))

{:hash hash
 :hash-file hash-file}
