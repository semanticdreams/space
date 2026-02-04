(local HackerNews (require :hackernews))

(var client nil)
(fn ensure-client []
    (if client
        client
        (do
            (set client (HackerNews {}))
            client)))

(fn next-list-key [kind]
    (.. "hackernews-story-list:" (or kind "stories")))

{:ensure-client ensure-client
 :next-list-key next-list-key}
