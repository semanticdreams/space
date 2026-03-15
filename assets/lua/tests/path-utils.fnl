(local fs (require :fs))

(fn canonical-path [path]
  (if (not path)
      nil
      (do
        (local (ok absolute-or-error) (pcall fs.absolute path))
        (local absolute (if ok absolute-or-error path))
        (local slashes (string.gsub absolute "\\" "/"))
        (string.lower slashes))))

(fn paths-eq [a b]
  (= (canonical-path a) (canonical-path b)))

{:canonical-path canonical-path
 :paths-eq paths-eq}
