(local glm (require :glm))

(fn contact-key-from-values [touch-id finger-id]
  (.. (tostring (or touch-id 0))
      ":"
      (tostring (or finger-id 0))))

(fn copy-table [source]
  (if source
      (do
        (local clone {})
        (each [k v (pairs source)]
          (set (. clone k) v))
        clone)
      nil))

(fn remove-first! [items target]
  (var idx nil)
  (each [i item (ipairs items)]
    (when (and (not idx) (= item target))
      (set idx i)))
  (when idx
    (table.remove items idx)))

(fn distance [a b]
  (if (and a b)
      (glm.length
        (glm.vec2 (- (or a.x 0) (or b.x 0))
                  (- (or a.y 0) (or b.y 0))))
      0))

(fn centroid-for-contacts [contacts previous?]
  (local count (length contacts))
  (if (<= count 0)
      nil
      (do
        (var sum-x 0)
        (var sum-y 0)
        (each [_ contact (ipairs contacts)]
          (set sum-x (+ sum-x (or (if previous? contact.prev-x contact.x) 0)))
          (set sum-y (+ sum-y (or (if previous? contact.prev-y contact.y) 0))))
        {:x (/ sum-x count)
         :y (/ sum-y count)})))

(fn span-for-contacts [contacts previous?]
  (if (< (length contacts) 2)
      0
      (do
        (local a (. contacts 1))
        (local b (. contacts 2))
        (distance {:x (or (if previous? a.prev-x a.x) 0)
                   :y (or (if previous? a.prev-y a.y) 0)}
                  {:x (or (if previous? b.prev-x b.x) 0)
                   :y (or (if previous? b.prev-y b.y) 0)}))))

(fn build-contact [payload sequence existing]
  (local prior (or existing payload {}))
  (local x (or (and payload payload.x) (and existing existing.x) 0))
  (local y (or (and payload payload.y) (and existing existing.y) 0))
  {:key (contact-key-from-values (and payload payload.touch-id)
                                 (and payload payload.finger-id))
   :touch-id (and payload payload.touch-id)
   :finger-id (and payload payload.finger-id)
   :x x
   :y y
   :xrel (or (and payload payload.xrel) 0)
   :yrel (or (and payload payload.yrel) 0)
   :pressure (or (and payload payload.pressure) (and existing existing.pressure))
   :timestamp (or (and payload payload.timestamp) (and existing existing.timestamp))
   :start-x (or (and existing existing.start-x) x)
   :start-y (or (and existing existing.start-y) y)
   :prev-x (or (and existing existing.x) x)
   :prev-y (or (and existing existing.y) y)
   :sequence (or (and existing existing.sequence) sequence)
   :source (copy-table payload)
   :previous-source (copy-table prior)})

(fn TouchSession []
  (var contacts-by-key {})
  (var contact-order [])
  (var sequence-counter 0)

  (fn key-from-payload [_self payload]
    (contact-key-from-values (and payload payload.touch-id)
                             (and payload payload.finger-id)))

  (fn count [_self]
    (length contact-order))

  (fn has-key? [_self key]
    (not (= (rawget contacts-by-key key) nil)))

  (fn get [_self key]
    (rawget contacts-by-key key))

  (fn contacts [_self]
    (local out [])
    (each [_ key (ipairs contact-order)]
      (local contact (rawget contacts-by-key key))
      (when contact
        (table.insert out contact)))
    out)

  (fn primary [self]
    (if (> (self:count) 0)
        (self:get (. contact-order 1))
        nil))

  (fn movement-distance [_self contact]
    (if contact
        (distance {:x contact.x :y contact.y}
                  {:x contact.start-x :y contact.start-y})
        0))

  (fn gesture-payload [self]
    (local active-contacts (self:contacts))
    (local centroid (centroid-for-contacts active-contacts false))
    (local previous-centroid (centroid-for-contacts active-contacts true))
    {:count (length active-contacts)
     :contacts active-contacts
     :centroid centroid
     :previous-centroid previous-centroid
     :delta (if (and centroid previous-centroid)
                {:x (- centroid.x previous-centroid.x)
                 :y (- centroid.y previous-centroid.y)}
                {:x 0 :y 0})
     :span (span-for-contacts active-contacts false)
     :previous-span (span-for-contacts active-contacts true)})

  (fn set-contact! [self payload]
    (local key (self:key-from-payload payload))
    (local existing (rawget contacts-by-key key))
    (when (not existing)
      (set sequence-counter (+ sequence-counter 1))
      (table.insert contact-order key))
    (local contact (build-contact payload sequence-counter existing))
    (rawset contacts-by-key key contact)
    contact)

  (fn clear-key! [_self key]
    (rawset contacts-by-key key nil)
    (remove-first! contact-order key)
    true)

  (fn on-touch-down [self payload]
    (self:set-contact! payload))

  (fn on-touch-motion [self payload]
    (self:set-contact! payload))

  (fn on-touch-up [self payload]
    (local key (self:key-from-payload payload))
    (local existing (rawget contacts-by-key key))
    (when existing
      (local contact (build-contact payload sequence-counter existing))
      (self:clear-key! key)
      contact))

  (fn clear [_self]
    (each [_ key (ipairs contact-order)]
      (rawset contacts-by-key key nil))
    (while (> (length contact-order) 0)
      (table.remove contact-order))
    (set sequence-counter 0)
    true)

  {:key-from-payload key-from-payload
   :count count
   :has-key? has-key?
   :get get
   :contacts contacts
   :primary primary
   :movement-distance movement-distance
   :gesture-payload gesture-payload
   :set-contact! set-contact!
   :clear-key! clear-key!
   :on-touch-down on-touch-down
   :on-touch-motion on-touch-motion
   :on-touch-up on-touch-up
   :clear clear})

TouchSession
