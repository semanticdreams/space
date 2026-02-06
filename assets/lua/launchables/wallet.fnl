(local WalletView (require :wallet-view))

{:name "Wallet"
 :run (fn []
        (local scene app.scene)
        (assert (and scene scene.add-panel-child) "Wallet launchable requires app.scene.add-panel-child")
        (scene:add-panel-child {:builder (WalletView {})}))}
