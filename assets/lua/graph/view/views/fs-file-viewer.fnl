(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))
(local VirtualInput (require :virtual-input))
(local Modifiers (require :input-modifiers))

(fn token-matches? [current expected]
  (assert current "token-matches? requires current token")
  (assert expected "token-matches? requires expected token")
  (and (= current.path expected.path)
       (= current.exists expected.exists)
       (= current.is-file expected.is-file)
       (= current.size expected.size)
       (= current.modified expected.modified)
       (= current.change-id expected.change-id)))

(fn changed-since-baseline? [buffer]
  (assert buffer "changed-since-baseline? requires buffer")
  (assert buffer.source "changed-since-baseline? requires buffer.source")
  (local current (buffer.source:current-token))
  (not (token-matches? current buffer.source.baseline-token)))

(fn status-label [kind detail]
  (if (= kind :dirty)
      "Unsaved changes"
      (= kind :saved)
      "Saved"
      (= kind :conflict)
      (.. "Conflict: " (if (= detail nil) "file changed externally" detail))
      (= kind :error)
      (.. "Error: " (if (= detail nil) "save failed" detail))
      (= kind :clean)
      "Clean"
      (error (.. "unsupported fs-file-viewer status: " (tostring kind)))))

(fn set-status [view kind detail]
  (set view.status-kind kind)
  (view.status-text:set-text (status-label kind detail)))

(fn update-dirty-status [input _buffer]
  (set-status input.viewer-view :dirty))

(fn save-view [view]
  (assert view "save-view requires view")
  (assert view.virtual-input "save-view requires view.virtual-input")
  (if (changed-since-baseline? view.virtual-input.buffer)
      (do
        (set-status view :conflict "file changed since token")
        false)
      (do
        (local buffer view.virtual-input.buffer)
        (local (ok result) (pcall buffer.save buffer))
        (if ok
            (do
              (view.virtual-input:refresh-viewport)
              (set-status view :saved)
              result)
            (do
              (local message (tostring result))
              (if (string.find message "file changed since token" 1 true)
                  (set-status view :conflict message)
                  (set-status view :error message))
              false)))))

(fn save-button-click [button _event]
  (save-view button.viewer-view))

(fn save-key? [payload]
  (and payload
       (Modifiers.ctrl-held? payload.mod)
       (if (= payload.key (string.byte "s"))
           true
           (= payload.key (string.byte "S"))
           true
           false)))

(fn route-key-down [view original-on-key-down input payload]
  (if (save-key? payload)
      (if (save-view view) true false)
      (original-on-key-down input payload)))

(fn open-external-click [button _event]
  (button.viewer-node:open-external))

(fn build-save-button [ctx]
  ctx.fs_file_viewer_save_button)

(fn build-edit-button [ctx]
  ctx.fs_file_viewer_edit_button)

(fn build-controls [ctx]
  ctx.fs_file_viewer_controls)

(fn build-status-text [ctx]
  ctx.fs_file_viewer_status_text)

(fn build-virtual-input [ctx]
  ctx.fs_file_viewer_virtual_input)

(fn set-viewer-node [button node]
  (set button.viewer-node node)
  button)

(fn set-viewer-view [button view]
  (set button.viewer-view view)
  button)

(fn make-button [ctx node text handler]
  (set-viewer-node
    ((Button {:text text
              :variant :ghost
              :on-click handler})
     ctx)
    node))

(fn make-save-button [ctx view]
  (set-viewer-view
    ((Button {:text "Save"
              :variant :ghost
              :on-click save-button-click})
     ctx)
    view))

(fn make-controls [ctx]
  ((Flex {:axis 1
          :xspacing 0.3
          :yalign :center
          :children [(FlexChild build-save-button 0)
                     (FlexChild build-edit-button 0)]})
   ctx))

(fn make-root [ctx]
  ((Flex {:axis 2
          :xalign :stretch
          :yspacing 0.35
          :children [(FlexChild build-controls 0)
                     (FlexChild build-status-text 0)
                     (FlexChild build-virtual-input 1)]})
   ctx))

(fn clear-context-fields [ctx]
  (set ctx.fs_file_viewer_save_button nil)
  (set ctx.fs_file_viewer_edit_button nil)
  (set ctx.fs_file_viewer_controls nil)
  (set ctx.fs_file_viewer_status_text nil)
  (set ctx.fs_file_viewer_virtual_input nil))

(fn FsFileViewerNodeView [node _opts]
  (fn build [ctx]
    (local build-ctx ctx)
    (assert build-ctx "FsFileViewerNodeView requires a build context")
    (assert node.buffer "FsFileViewerNodeView requires node.buffer")
    (local status-text ((Text {:text (status-label :clean)}) build-ctx))
    (local view {:virtual-input nil
                 :save-button nil
                 :edit-button nil
                 :status-text status-text
                 :layout nil
                 :status-kind :clean})
    (local virtual-input ((VirtualInput {:buffer node.buffer
                                         :line-count 24
                                         :column-count 100
                                         :on-change update-dirty-status})
                          build-ctx))
    (set virtual-input.viewer-view view)
    (set view.virtual-input virtual-input)
    (local original-on-key-down virtual-input.on-key-down)
    (set virtual-input.save (fn [_input] (save-view view)))
    (set virtual-input.on-key-down
         (fn [input payload]
           (route-key-down view original-on-key-down input payload)))
    (local save-button (make-save-button build-ctx view))
    (local edit-button (make-button build-ctx node "Edit externally" open-external-click))
    (set build-ctx.fs_file_viewer_virtual_input virtual-input)
    (set build-ctx.fs_file_viewer_save_button save-button)
    (set build-ctx.fs_file_viewer_edit_button edit-button)
    (set build-ctx.fs_file_viewer_status_text status-text)
    (local controls (make-controls build-ctx))
    (set build-ctx.fs_file_viewer_controls controls)
    (local root (make-root build-ctx))
    (clear-context-fields build-ctx)
    (set view.save-button save-button)
    (set view.edit-button edit-button)
    (set view.layout root.layout)
    (set view.drop
         (fn [_self]
           (root:drop)))
    view))

FsFileViewerNodeView
