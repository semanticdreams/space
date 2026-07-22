(fn slugify [text]
  (var result "")
  (each [c (string.gmatch (string.lower text) ".")]
    (if (string.match c "[%w]")
        (set result (.. result c))
        (= c ".")
        (set result (.. result "."))
        (= c "@")
        nil
        (= c "/")
        (set result (.. result "."))
        (set result (.. result "-"))))
  result)

(fn strip-www [host]
  (if (= (string.sub (string.lower host) 1 4) "www.")
      (string.sub host 5)
      host))

(fn strip-port [host]
  (or (string.match host "^([^:]+)")
      host))

(fn parse [url]
  (assert (= (type url) "string") "remote.parse requires a string url")
  (assert (> (# url) 0) "remote.parse requires a non-empty url")
  (assert (not (string.find url "?" 1 true)) "remote URL must not contain a query string")
  (assert (not (string.find url "#" 1 true)) "remote URL must not contain a fragment")
  (var host nil)
  (var host-raw nil)
  (var owner nil)
  (var name nil)
  (var remote-url url)
  (if (string.match url "^git@")
      (do
        (local (ssh-host ssh-rest) (string.match url "^git@([^:]+):(.+)$"))
        (assert ssh-host (.. "cannot parse SSH URL: " url))
        (assert (not (string.find ssh-host "@" 1 true)) (.. "SSH remote URL must not contain credentials: " url))
        (set host-raw (strip-port (string.lower (strip-www ssh-host))))
        (set host (slugify host-raw))
        (local repo-path (or (string.match ssh-rest "^(.-)%.git$") ssh-rest))
        (local (ns proj) (string.match repo-path "^(.+)/([^/]+)$"))
        (assert ns (.. "cannot find repo owner/name in URL: " url))
        (set owner ns)
        (set name proj))
      (string.match url "^https?://")
      (do
        (local (https-host https-rest) (string.match url "^https?://([^/]+)/(.+)$"))
        (assert https-host (.. "cannot parse HTTPS URL: " url))
        (assert (not (string.find https-host "@" 1 true)) (.. "HTTPS remote URL must not contain credentials: " url))
        (set host-raw (strip-port (string.lower (strip-www https-host))))
        (set host (slugify host-raw))
        (local repo-path (or (string.match https-rest "^(.-)%.git$") https-rest))
        (local (ns proj) (string.match repo-path "^(.+)/([^/]+)$"))
        (assert ns (.. "cannot find repo owner/name in URL: " url))
        (set owner ns)
        (set name proj))
      (string.match url "^ssh://")
      (do
        (local (ssh-host ssh-rest) (string.match url "^ssh://git@([^/]+)/(.+)$"))
        (assert ssh-host (.. "cannot parse SSH (ssh://) URL: " url))
        (assert (not (string.find ssh-host "@" 1 true)) (.. "SSH remote URL must not contain credentials: " url))
        (set host-raw (strip-port (string.lower (strip-www ssh-host))))
        (set host (slugify host-raw))
        (local repo-path (or (string.match ssh-rest "^(.-)%.git$") ssh-rest))
        (local (ns proj) (string.match repo-path "^(.+)/([^/]+)$"))
        (assert ns (.. "cannot find repo owner/name in URL: " url))
        (set owner ns)
        (set name proj))
       (error (.. "cannot parse remote URL: " url)))
  (assert host "could not determine host")
  (assert owner "could not determine owner")
  (assert name "could not determine repo name")
  (local repo-id (string.format "%s-%s-%s" host (slugify owner) (slugify name)))
  (local host-type (if (= host "github.com")
                       :github
                       (= host "gitlab.com")
                       :gitlab
                       :unknown))
  {:remote-url remote-url
   :host host-type
   :host-key host
   :host-raw host-raw
   :owner owner
   :name name
   :repo-id repo-id})

(fn derive-repo-id [url]
  (. (parse url) :repo-id))

(fn detect-host [url]
  (. (parse url) :host))

{:parse parse
 :derive-repo-id derive-repo-id
 :detect-host detect-host}
