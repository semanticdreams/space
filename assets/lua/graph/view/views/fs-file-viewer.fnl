(local {: Flex : FlexChild} (require :flex))
(local Button (require :button))
(local Text (require :text))

(fn zero-if-nil [value]
  (if (= value nil) 0 value))

(fn text-if-present [window]
  (if (and window window.text) window.text ""))

(fn metadata-label [window]
  (if window
      (string.format "Offset %s  Bytes %s  Size %s"
                     (tostring (zero-if-nil window.offset))
                     (tostring (zero-if-nil window.bytes-read))
                     (tostring (zero-if-nil window.size)))
      "Offset 0  Bytes 0  Size 0"))

(fn update-window-text [view window]
  (view.content-text:set-text (text-if-present window))
  (view.metadata-text:set-text (metadata-label window)))

(fn previous-button-click [button _event]
  (button.viewer-node:previous-window))

(fn next-button-click [button _event]
  (button.viewer-node:next-window))

(fn refresh-button-click [button _event]
  (button.viewer-node:refresh-window))

(fn open-external-click [button _event]
  (button.viewer-node:open-external))

(fn build-previous-button [ctx]
  ctx.fs_file_viewer_previous_button)

(fn build-next-button [ctx]
  ctx.fs_file_viewer_next_button)

(fn build-refresh-button [ctx]
  ctx.fs_file_viewer_refresh_button)

(fn build-edit-button [ctx]
  ctx.fs_file_viewer_edit_button)

(fn build-controls [ctx]
  ctx.fs_file_viewer_controls)

(fn build-metadata-text [ctx]
  ctx.fs_file_viewer_metadata_text)

(fn build-content-button [ctx]
  ctx.fs_file_viewer_content_button)

(fn build-content-text [ctx]
  ctx.fs_file_viewer_content_text)

(fn set-viewer-node [button node]
  (set button.viewer-node node)
  button)

(fn make-button [ctx node text handler]
  (set-viewer-node
    ((Button {:text text
              :variant :ghost
              :on-click handler})
     ctx)
    node))

(fn make-content-button [ctx node]
  (set-viewer-node
    ((Button {:child build-content-text
              :xalign :start
              :yalign :start
              :on-double-click open-external-click})
     ctx)
    node))

(fn make-controls [ctx]
  ((Flex {:axis 1
          :xspacing 0.3
          :yalign :center
          :children [(FlexChild build-previous-button 0)
                     (FlexChild build-next-button 0)
                     (FlexChild build-refresh-button 0)
                     (FlexChild build-edit-button 0)]})
   ctx))

(fn make-root [ctx]
  ((Flex {:axis 2
          :xalign :stretch
          :yspacing 0.35
          :children [(FlexChild build-controls 0)
                     (FlexChild build-metadata-text 0)
                     (FlexChild build-content-button 1)]})
   ctx))

(fn clear-context-fields [ctx]
  (set ctx.fs_file_viewer_previous_button nil)
  (set ctx.fs_file_viewer_next_button nil)
  (set ctx.fs_file_viewer_refresh_button nil)
  (set ctx.fs_file_viewer_edit_button nil)
  (set ctx.fs_file_viewer_controls nil)
  (set ctx.fs_file_viewer_metadata_text nil)
  (set ctx.fs_file_viewer_content_button nil)
  (set ctx.fs_file_viewer_content_text nil))

(fn FsFileViewerNodeView [node _opts]
  (fn build [ctx]
    (local build-ctx ctx)
    (assert build-ctx "FsFileViewerNodeView requires a build context")
    (local content-text ((Text {:text ""}) build-ctx))
    (local metadata-text ((Text {:text (metadata-label nil)}) build-ctx))
    (set build-ctx.fs_file_viewer_content_text content-text)
    (local previous-button (make-button build-ctx node "Previous" previous-button-click))
    (local next-button (make-button build-ctx node "Next" next-button-click))
    (local refresh-button (make-button build-ctx node "Refresh" refresh-button-click))
    (local edit-button (make-button build-ctx node "Edit externally" open-external-click))
    (set build-ctx.fs_file_viewer_previous_button previous-button)
    (set build-ctx.fs_file_viewer_next_button next-button)
    (set build-ctx.fs_file_viewer_refresh_button refresh-button)
    (set build-ctx.fs_file_viewer_edit_button edit-button)
    (local content-button (make-content-button build-ctx node))
    (set build-ctx.fs_file_viewer_content_button content-button)
    (set build-ctx.fs_file_viewer_metadata_text metadata-text)
    (local controls (make-controls build-ctx))
    (set build-ctx.fs_file_viewer_controls controls)
    (local root (make-root build-ctx))
    (clear-context-fields build-ctx)
    (local view {:previous-button previous-button
                 :next-button next-button
                 :refresh-button refresh-button
                 :edit-button edit-button
                 :content-button content-button
                 :content-text content-text
                 :metadata-text metadata-text
                 :layout root.layout})
    (local handler (fn [window]
                    (update-window-text view window)))
    (node.window-changed:connect handler)
    (node:refresh-window)
    (set view.drop
         (fn [_self]
           (node.window-changed:disconnect handler true)
           (root:drop)))
    view))

FsFileViewerNodeView
