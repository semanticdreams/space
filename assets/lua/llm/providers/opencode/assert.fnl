(fn assert-callback [cb name]
  (assert (= (type cb) "function") (.. name " requires a function for on_response")))

{:assert-callback assert-callback}
