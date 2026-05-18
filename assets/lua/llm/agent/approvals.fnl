;; Agent approvals — centralizes risk decisions for high-risk capabilities.
;; Risk levels: :normal, :filesystem-read, :filesystem-write, :destructive, :shell

(local valid-risks
  {:normal true
   :filesystem-read true
   :filesystem-write true
   :destructive true
   :shell true})

(fn AgentApprovals [opts]
  (local policy (or opts.policy {}))
  (var decisions [])

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

  (fn request-risk [self risk reason callbacks]
    (assert (= (type callbacks) "table") "request-risk requires callbacks table")
    (assert (= (type callbacks.on-approved) "function") "request-risk requires on-approved callback")
    (assert (= (type callbacks.on-denied) "function") "request-risk requires on-denied callback")
    (local state (self:check-risk risk))
    (if (= state :approved)
        (do
          (self:record-decision {:risk risk :reason reason :decision :approved})
          (callbacks.on-approved {:risk risk :reason reason}))
        (= state :denied)
        (do
          (self:record-decision {:risk risk :reason reason :decision :denied})
          (callbacks.on-denied {:risk risk :reason reason}))
        (do
          (callbacks.on-denied {:risk risk
                                :reason reason
                                :needs-approval true})
          false)))

  (fn record-decision [self decision]
    (table.insert decisions decision))

  {:check-risk check-risk
   :request-risk request-risk
   :record-decision record-decision})

{:AgentApprovals AgentApprovals}
