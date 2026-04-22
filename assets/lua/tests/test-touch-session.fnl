(local tests [])
(local TouchSession (require :touch-session))

(fn string-key-payload [touch-id finger-id x y]
  (local payload {:x x
                  :y y
                  :xrel 0
                  :yrel 0
                  :pressure 1.0
                  :timestamp 1})
  (tset payload "touch-id" touch-id)
  (tset payload "finger-id" finger-id)
  payload)

(fn touch-session-distinguishes-contacts-from-string-key-payloads []
  (local session (TouchSession))
  (session:on-touch-down (string-key-payload 7 301 10 20))
  (session:on-touch-down (string-key-payload 7 302 30 40))
  (assert (= (session:count) 2))
  (local contacts (session:contacts))
  (assert (= (# contacts) 2))
  (assert (= (rawget (. contacts 1) "touch-id") 7))
  (assert (= (rawget (. contacts 1) "finger-id") 301))
  (assert (= (rawget (. contacts 2) "touch-id") 7))
  (assert (= (rawget (. contacts 2) "finger-id") 302))
  (local ids {})
  (each [_ contact (ipairs contacts)]
    (table.insert ids (.. (tostring (rawget contact "touch-id"))
                          ":"
                          (tostring (rawget contact "finger-id")))))
  (assert (= (. ids 1) "7:301"))
  (assert (= (. ids 2) "7:302")))

(table.insert tests {:name "TouchSession distinguishes contacts from string-key payloads"
                     :fn touch-session-distinguishes-contacts-from-string-key-payloads})

(local main
  (fn []
    (local runner (require :tests/runner))
    (runner.run-tests {:name "touch-session"
                       :tests tests})))

{:name "touch-session"
 :main main}
