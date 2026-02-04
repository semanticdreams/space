(local Uuid (require :uuid))

(fn new-id [prefix]
  (local raw (Uuid.v4))
  (if prefix
      (.. (tostring prefix) "-" raw)
      raw))

{:new-id new-id}
