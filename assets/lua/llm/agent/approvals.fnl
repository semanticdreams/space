;; Agent approvals — centralizes risk decisions for high-risk capabilities.
;; Risk levels: :normal, :filesystem-read, :filesystem-write, :destructive, :shell

(local Signal (require :signal))

(local valid-risks
  {:normal true
   :filesystem-read true
   :filesystem-write true
   :destructive true
   :shell true})

(fn AgentApprovals [opts]
  (local policy (or opts.policy {}))
  (var decisions [])
  (var pending-requests {})
  (var pending-by-key {})
  (var approval-grants {})
  (var request-count 0)
  (local requested (Signal))

  (fn request-key [risk reason context]
    (local ctx (or context {}))
    (table.concat [(tostring risk)
                   (or ctx.tool "")
                   (or ctx.source "")
                   (or reason "")]
                  "\n"))

  (fn grant-key [key]
    (tset approval-grants key (+ (or (. approval-grants key) 0) 1)))

  (fn consume-grant [key]
    (local count (or (. approval-grants key) 0))
    (if (> count 0)
        (do
          (if (> count 1)
              (tset approval-grants key (- count 1))
              (tset approval-grants key nil))
          true)
        false))

  (fn check-risk [self risk context]
    (assert (. valid-risks risk) (.. "unknown risk level: " (tostring risk)))
    (if (= risk :normal)
        :approved
        (do
          (local policy-action (or (. policy risk) :ask))
          (if (= policy-action :auto)
              :approved
              (= policy-action :deny)
              :denied
              :needs-approval))))

  (fn request-risk [self risk reason callbacks context]
    (assert (= (type callbacks) "table") "request-risk requires callbacks table")
    (assert (= (type callbacks.on-approved) "function") "request-risk requires on-approved callback")
    (assert (= (type callbacks.on-denied) "function") "request-risk requires on-denied callback")
    (local state (self:check-risk risk))
    (local key (request-key risk reason context))
    (if (= state :approved)
        (do
          (self:record-decision {:risk risk :reason reason :decision :approved})
          (callbacks.on-approved {:risk risk :reason reason}))
        (= state :denied)
        (do
          (self:record-decision {:risk risk :reason reason :decision :denied})
          (callbacks.on-denied {:risk risk :reason reason}))
        (consume-grant key)
        (do
          (self:record-decision {:risk risk
                                  :reason reason
                                  :decision :approved
                                  :approved-from :approval-grant})
          (callbacks.on-approved {:risk risk
                                  :reason reason
                                  :approved-from :approval-grant}))
        (. pending-by-key key)
        (do
          (local request (. pending-by-key key))
          (table.insert request.waiters callbacks)
          (requested:emit request)
          false)
        (do
          (set request-count (+ request-count 1))
          (local request-id (.. "approval-" request-count))
          (var resolved? false)
          (local request {:id request-id
                          :risk risk
                          :reason reason
                          :context (or context {})
                          :needs-approval true
                          :created-at (os.time)
                          :sequence request-count
                          :waiters [callbacks]})
          (fn finish [decision]
            (when (not resolved?)
              (set resolved? true)
              (tset pending-requests request-id nil)
              (tset pending-by-key key nil)
              (when (and (= decision :approved)
                         (and context context.grant-on-approve))
                (grant-key key))
              (self:record-decision {:risk risk
                                      :reason reason
                                      :decision decision
                                      :request-id request-id})
              (each [_ waiter (ipairs request.waiters)]
                ((if (= decision :approved) waiter.on-approved waiter.on-denied)
                 {:risk risk
                  :reason reason
                  :request-id request-id}))
              (requested:emit nil)))
          (set request.approve
               (fn [_self]
                 (finish :approved)))
          (set request.deny
               (fn [_self]
                 (finish :denied)))
          (tset pending-requests request-id request)
          (tset pending-by-key key request)
          (requested:emit request)
          false)))

  (fn record-decision [self decision]
    (table.insert decisions decision))

  (fn list-pending [_self]
    (local result [])
    (each [_ request (pairs pending-requests)]
      (table.insert result request))
    (table.sort result
                (fn [a b]
                  (if (= (or a.created-at 0) (or b.created-at 0))
                      (< (or a.sequence 0) (or b.sequence 0))
                      (< (or a.created-at 0) (or b.created-at 0)))))
    result)

  {:check-risk check-risk
   :request-risk request-risk
   :record-decision record-decision
   :list-pending list-pending
   :requested requested})

{:AgentApprovals AgentApprovals}
