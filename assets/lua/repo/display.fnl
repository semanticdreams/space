(fn safe-display-url [repo]
  (each [_ field (ipairs [:host-raw :owner :name])]
    (local v (. repo field))
    (assert (= (type v) "string") (.. "repo." field " must be a string"))
    (assert (not (string.find v "@" 1 true)) (.. "repo." field " must not contain @: " v))
    (assert (not (string.find v "?" 1 true)) (.. "repo." field " must not contain a query string: " v))
    (assert (not (string.find v "#" 1 true)) (.. "repo." field " must not contain a fragment: " v)))
  (.. "https://" repo.host-raw "/" repo.owner "/" repo.name ".git"))

(fn safe-repo-summary [repo]
  {:id repo.id
   :remote-url (safe-display-url repo)
   :host repo.host
   :owner repo.owner
   :name repo.name
   :default-branch repo.default-branch
   :profile repo.profile
   :created-at repo.created-at})

{:safe-display-url safe-display-url
 :safe-repo-summary safe-repo-summary}
