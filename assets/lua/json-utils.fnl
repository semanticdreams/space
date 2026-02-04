(local fs (require :fs))
(local json (require :json))

(assert fs "json-utils requires fs module")
(assert json "json-utils requires json module")

(fn write-json-atomic! [path payload]
    (local tmp-path (.. path ".tmp"))
    (fs.write-file tmp-path payload)
    (local (ok err) (pcall fs.rename tmp-path path))
    (when (not ok)
        (pcall (fn [] (fs.remove tmp-path)))
        (local message (string.format "json-utils failed to rename %s to %s: %s"
                                      tmp-path
                                      path
                                      err))
        (error message)))

(fn write-json! [path data opts]
    (local options (or opts {}))
    (local payload (json.dumps data))
    (if (= options.atomic? false)
        (fs.write-file path payload)
        (write-json-atomic! path payload))
    true)

{:write-json! write-json!}
