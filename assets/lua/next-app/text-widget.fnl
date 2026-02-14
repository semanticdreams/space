(local NextLayout (require :next-app/layout))
(local Node NextLayout.Node)

(local TextStyle (require :text-style))
(local {: codepoints-from-text
        : copy-codepoints} (require :text-utils))

(fn TextWidget [opts]
  (local options (or opts {}))
  (local style (or options.style (TextStyle options)))
  (assert style.font "NextApp TextWidget requires a resolved font")
  (var text (or options.text ""))
  (var codepoints (codepoints-from-text text))
  (var visible? (if (= options.visible? false) false true))
  (var content-dirty? true)
  (var registered? false)
  (var registered-batcher nil)
  (var node nil)
  (var last-batcher nil)
  (var cache-valid? false)
  (var cached-width 0.0)
  (var cached-height 0.0)

  (local newline-codepoint (string.byte "\n"))
  (local carriage-return-codepoint (string.byte "\r"))

  (fn fallback-glyph [codepoint]
    (or (. style.font.glyph-map codepoint)
        (. style.font.glyph-map 65533)))

  (fn line-height []
    (local metrics style.font.metadata.metrics)
    (local desc (or metrics.descender 0))
    (local asc (or metrics.ascender 0))
    (local fallback (+ asc (math.abs desc)))
    (* style.scale (or metrics.lineHeight fallback)))

  (fn rebuild-measure-cache []
    (var current-width 0.0)
    (var max-width 0.0)
    (var line-count 1)
    (var i 1)
    (local total (# codepoints))
    (while (<= i total)
      (local codepoint (. codepoints i))
      (if (or (= codepoint newline-codepoint)
              (= codepoint carriage-return-codepoint))
          (do
            (set max-width (math.max max-width current-width))
            (set current-width 0.0)
            (set line-count (+ line-count 1))
            (when (and (= codepoint carriage-return-codepoint)
                       (< i total)
                       (= (. codepoints (+ i 1)) newline-codepoint))
              (set i (+ i 1))))
          (do
            (local glyph (fallback-glyph codepoint))
            (set current-width (+ current-width (* glyph.advance style.scale)))))
      (set i (+ i 1)))
    (set max-width (math.max max-width current-width))
    (set cached-width max-width)
    (set cached-height (* (line-height) line-count))
    (set cache-valid? true))

  (fn invalidate-cache []
    (set cache-valid? false))

  (fn emit-options [self clip-matrix]
    {:font style.font
     :scale style.scale
     :codepoints codepoints
     :group-matrix self.world-matrix
     :clip-matrix clip-matrix})

  (fn measure-fn [self _mw _mh _md]
    (when (not cache-valid?)
      (rebuild-measure-cache))
    (self:set-measure cached-width cached-height 0))

  (fn layout-fn [self width height depth]
    (self:set-size width height depth {:mark-dirty? false}))

  (set node
       (Node.new {:name (or options.name "next-text")
                  :measure-fn measure-fn
                  :layout-fn layout-fn
                  :width 0
                  :height 0
                  :depth 0}))

  (set node.set-text
       (fn [self next-text]
         (set text (or next-text ""))
         (set codepoints (codepoints-from-text text))
         (invalidate-cache)
         (set content-dirty? true)
         (self:mark-measure-dirty)
         (self:mark-render-dirty)))

  (set node.set-codepoints
       (fn [self next-codepoints]
         (set codepoints (copy-codepoints next-codepoints))
         (invalidate-cache)
         (set content-dirty? true)
         (self:mark-measure-dirty)
         (self:mark-render-dirty)))

  (set node.emit-ssbo
       (fn [self batcher clip-matrix]
         (assert batcher.upsert-text "NextApp TextWidget requires batcher.upsert-text")
         (assert batcher.update-text-transform "NextApp TextWidget requires batcher.update-text-transform")
         (assert batcher.remove-text "NextApp TextWidget requires batcher.remove-text")
         (set last-batcher batcher)
         (when (and registered?
                    registered-batcher
                    (not (= registered-batcher batcher)))
           (registered-batcher:remove-text self)
           (set registered? false)
           (set registered-batcher nil))
         (if visible?
             (if (and batcher.upsert-text
                      registered?
                      (= registered-batcher batcher)
                      (not content-dirty?)
                      batcher.update-text-transform)
                 (batcher:update-text-transform self
                                                {:group-matrix self.world-matrix
                                                 :clip-matrix clip-matrix})
                 (do
                   (batcher:upsert-text self (emit-options self clip-matrix))
                   (set registered? true)
                   (set registered-batcher batcher)
                   (set content-dirty? false)))
             (do
               (batcher:remove-text self)
               (set registered? false)
               (set registered-batcher nil)))))

  (set node.get-text
       (fn [_self] text))

  (set node.set-visible
       (fn [self value]
         (local next-visible (not (= value false)))
         (when (not (= visible? next-visible))
           (set visible? next-visible)
           (when (and (not visible?) last-batcher last-batcher.remove-text)
             (last-batcher:remove-text self))
           (when (not visible?)
             (set registered? false)
             (set registered-batcher nil))
           (self:mark-layout-dirty)
           (self:mark-render-dirty))))

  (set node.visible?
       (fn [_self] visible?))

  (set node.style style)
  (set node._measure-cache-valid?
       (fn [_self] cache-valid?))
  (set node.drop
       (fn [self]
         (when (and last-batcher last-batcher.remove-text)
           (last-batcher:remove-text self))
         (set registered? false)
         (set registered-batcher nil)
         (set last-batcher nil)))
  node)

TextWidget
