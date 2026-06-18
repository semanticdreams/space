(local windows? (= (string.sub (or package.config "") 1 1) "\\"))

(fn path-separator? [c]
  (or (= c "/")
      (and windows? (= c "\\"))))

{:path-separator? path-separator?}
