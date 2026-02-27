(local WalletView (require :wallet-view))
(local Persistence (require :scene-panel-persistence))

(local kind "scene-wallet-dialog")
(local restorer-module "launchables/wallet")

(fn open-panel [opts]
  (local options (or opts {}))
  (local scene (assert (or options.scene options.target app.scene)
                       "Wallet launchable requires scene target"))
  (assert scene.add-panel-child "Wallet launchable target requires :add-panel-child")
  (local transform (Persistence.panel-transform-options (or options.panel {})))
  (scene:add-panel-child {:builder (WalletView {})
                          :position transform.position
                          :rotation transform.rotation
                          :persistence {:kind kind
                                        :restorer-module restorer-module}}))

(fn restore [opts]
  (open-panel opts))

{:name "Wallet"
 :kind kind
 :restorer-module restorer-module
 :open-panel open-panel
 :restore restore
 :run (fn []
        (open-panel {:scene app.scene}))}
