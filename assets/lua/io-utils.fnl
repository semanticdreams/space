(fn read-file [path]
  (local file (io.open path "r"))
  (if file
      (do
        (local content (file:read "*all"))
        (file:close)
        content)
      (error (.. "Could not open file: " path))))

{:read-file read-file}
