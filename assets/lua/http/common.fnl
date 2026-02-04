(local json (require :json))

(local HttpCommon {})

(fn percent-encode [value]
  (string.gsub value "[^%w%-_%.~]" (fn [c] (string.format "%%%02X" (string.byte c)))))

(set HttpCommon.percent-encode percent-encode)

(fn encode-query [params]
  (if (or (not params) (= (next params) nil))
      ""
      (do
        (var parts [])
        (each [key value (pairs params)]
          (local encoded-key (percent-encode (tostring key)))
          (if (= (type value) :table)
              (each [_ item (ipairs value)]
                (table.insert parts (.. encoded-key "[]=" (percent-encode (tostring item)))))
              (when (not (= value nil))
                (table.insert parts (.. encoded-key "=" (percent-encode (tostring value)))))))
        (if (> (# parts) 0)
            (.. "?" (table.concat parts "&"))
            ""))))

(set HttpCommon.encode-query encode-query)

(fn normalize-headers [headers]
  (local out {})
  (when headers
    (each [_ pair (ipairs headers)]
      (local name (. pair 1))
      (local value (. pair 2))
      (when (and name value)
        (set (. out (string.lower name)) value))))
  out)

(set HttpCommon.normalize-headers normalize-headers)

(fn decode-json [body]
  (if (and json body (> (# body) 0))
      (do
        (local (ok parsed) (pcall json.loads body))
        (if ok parsed nil))
      nil))

(set HttpCommon.decode-json decode-json)

(fn decode-json! [body context]
  (assert json "http/common requires the json module")
  (local (ok parsed) (pcall json.loads body))
  (if ok
      parsed
      (error (.. (or context "Failed to decode JSON") ": " parsed))))

(set HttpCommon.decode-json! decode-json!)

(fn take-buffered [buffered id]
  (var found nil)
  (var idx 1)
  (while (<= idx (# buffered))
    (local entry (. buffered idx))
    (if (= entry.id id)
        (do
          (table.remove buffered idx)
          (set found entry)
          (set idx (+ (# buffered) 1)))
        (set idx (+ idx 1))))
  found)

(set HttpCommon.take-buffered take-buffered)

(fn await-response [http-binding buffered id timeout message]
  (assert http-binding "http/common await-response requires http binding")
  (local deadline (and timeout (+ (os.clock) timeout)))
  (var result (take-buffered buffered id))
  (while (not result)
    (each [_ res (ipairs (http-binding.poll 0))]
      (if (= res.id id)
          (set result res)
          (table.insert buffered res)))
    (when (and (not result) deadline (> (os.clock) deadline))
      (error (or message (.. "HTTP request timed out waiting for response " id)))))
  result)

(set HttpCommon.await-response await-response)

(fn reset-buffer! [buffered]
  (while (> (# buffered) 0)
    (table.remove buffered (# buffered)))
  buffered)

(set HttpCommon.reset-buffer! reset-buffer!)

(fn poll-until [poll-fn done? timeout message]
  (assert poll-fn "poll-until requires a poll function")
  (assert done? "poll-until requires a completion predicate")
  (local deadline (and timeout (+ (os.clock) timeout)))
  (while (not (done?))
    (poll-fn)
    (when (and deadline (> (os.clock) deadline))
      (error (or message "timeout waiting for response")))))

(set HttpCommon.poll-until poll-until)

HttpCommon
