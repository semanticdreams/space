;; Agent approvals — centralizes risk decisions for high-risk capabilities.
;; Risk levels: :normal, :filesystem-read, :filesystem-write, :destructive, :shell

(local fs (require :fs))
(local json (require :json))
(local JsonUtils (require :json-utils))
(local Signal (require :signal))

(local valid-risks
  {:normal true
   :filesystem-read true
   :filesystem-write true
   :destructive true
   :shell true})

(fn AgentApprovals [opts]
  (local options (or opts {}))
  (local policy (or options.policy {}))
  (local grants-path
    (or options.grants-path
        (and options.data-dir (fs.join-path options.data-dir "approval-grants.json"))))
  (var decisions [])
  (var pending-requests {})
  (var pending-by-key {})
  (var approval-grants {})
  (var always-grants {})
  (var request-count 0)
  (local requested (Signal))

  (fn sorted-grant-keys []
    (local keys [])
    (each [key enabled? (pairs always-grants)]
      (when enabled?
        (table.insert keys key)))
    (table.sort keys)
    keys)

  (fn persist-always-grants! []
    (when grants-path
      (local parent (fs.parent grants-path))
      (when (and parent (> (# parent) 0))
        (fs.create-dirs parent))
      (JsonUtils.write-json! grants-path
                             {:version 1
                              :always_grants (sorted-grant-keys)})))

  (fn load-always-grants! []
    (when (and grants-path (fs.exists grants-path))
      (local parsed (json.loads (fs.read-file grants-path)))
      (assert (= parsed.version 1)
              "AgentApprovals persistent grants file has unsupported version")
      (assert (= (type parsed.always_grants) "table")
              "AgentApprovals persistent grants file requires always_grants array")
      (set always-grants {})
      (each [idx key (ipairs parsed.always_grants)]
        (assert (= (type key) "string")
                (.. "AgentApprovals persistent grant key must be string at index " (tostring idx)))
        (tset always-grants key true))))

  (fn request-key [risk reason context]
    (local ctx (or context {}))
    (table.concat [(tostring risk)
                   (or ctx.tool "")
                   (or ctx.source "")
                   (or ctx.args_canonical "")
                   (or ctx.args_hash "")]
                  "\n"))

  (fn grant-key [key always?]
    (if always?
        (do
          (tset always-grants key true)
          (persist-always-grants!))
        (tset approval-grants key (+ (or (. approval-grants key) 0) 1))))

  (fn consume-grant [key]
    (if (. always-grants key)
        :always
        (do
          (local count (or (. approval-grants key) 0))
          (if (> count 0)
              (do
                (if (> count 1)
                    (tset approval-grants key (- count 1))
                    (tset approval-grants key nil))
                :once)
              nil))))

  (fn grant-result [risk reason grant-kind]
    {:risk risk
     :reason reason
     :approved-from (if (= grant-kind :always)
                        :always-approval-grant
                        :approval-grant)})

  (fn request-summary [request-id risk reason context request-sequence waiters]
    (local ctx (or context {}))
    {:id request-id
     :risk risk
     :reason reason
     :context ctx
     :tool ctx.tool
     :source ctx.source
     :args_hash ctx.args_hash
     :args_canonical ctx.args_canonical
     :args_preview ctx.args_preview
     :needs-approval true
     :created-at (os.time)
     :sequence request-sequence
     :waiters waiters})

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
    (local consumed-grant (if (= state :needs-approval)
                              (consume-grant key)
                              nil))
    (if (= state :approved)
        (do
          (self:record-decision {:risk risk :reason reason :decision :approved})
          (callbacks.on-approved {:risk risk :reason reason}))
        (= state :denied)
        (do
          (self:record-decision {:risk risk :reason reason :decision :denied})
          (callbacks.on-denied {:risk risk :reason reason}))
        consumed-grant
        (do
          (local approval (grant-result risk reason consumed-grant))
          (self:record-decision {:risk risk
                                  :reason reason
                                  :decision :approved
                                  :approved-from approval.approved-from})
          (callbacks.on-approved approval))
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
          (local request (request-summary request-id risk reason context request-count [callbacks]))
          (fn finish [decision opts]
            (when (not resolved?)
              (set resolved? true)
              (tset pending-requests request-id nil)
              (tset pending-by-key key nil)
              (when (and (= decision :approved)
                         (and context context.grant-on-approve))
                (when (and opts opts.always)
                  (assert context.args_hash
                          "always approval requires exact tool arguments"))
                (grant-key key (and opts opts.always)))
              (self:record-decision {:risk risk
                                      :reason reason
                                      :decision decision
                                      :request-id request-id
                                      :grant (and (= decision :approved)
                                                  (if (and opts opts.always) :always :once))})
              (each [_ waiter (ipairs request.waiters)]
                ((if (= decision :approved) waiter.on-approved waiter.on-denied)
                 {:risk risk
                  :reason reason
                  :request-id request-id
                  :grant (and (= decision :approved)
                              (if (and opts opts.always) :always :once))}))
              (requested:emit nil)))
          (set request.approve
               (fn [_self opts]
                 (finish :approved opts)))
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

  (load-always-grants!)

  {:check-risk check-risk
   :request-risk request-risk
   :record-decision record-decision
   :list-pending list-pending
   :requested requested})

{:AgentApprovals AgentApprovals}
