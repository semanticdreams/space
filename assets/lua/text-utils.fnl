(local glm (require :glm))
(local TextStyle (require :text-style))

(local newline-codepoint (string.byte "\n"))
(local carriage-return-codepoint (string.byte "\r"))

(local colors (require :colors))
(fn get-theme-text-color [ctx]
  (local theme (and ctx ctx.theme))
  (when theme
    (local text-colors theme.text)
    (and text-colors
         (or text-colors.foreground text-colors.color))))

(fn resolve-style [ctx opts]
  (local default-color
    (or opts.color
        (get-theme-text-color ctx)
        (glm.vec4 1 0 0 1)))
  (or opts.style (TextStyle {:color default-color})))

(fn fallback-glyph [font codepoint]
  (or (. font.glyph-map codepoint)
      (. font.glyph-map 65533)))

(fn finite-number? [value]
  (and (= (type value) :number)
       (= value value)
       (not (= value math.huge))
       (not (= value (- math.huge)))))

(fn glyph-advance [style codepoint]
  (local glyph (fallback-glyph style.font codepoint))
  (* glyph.advance style.scale))

(fn line-height [style]
  (local metrics (and style style.font style.font.metadata style.font.metadata.metrics))
  (local desc (and metrics metrics.descender))
  (local asc (and metrics metrics.ascender))
  (local fallback (+ (or asc 0)
                     (math.abs (or desc 0))))
  (local raw (or (and metrics metrics.lineHeight) fallback))
  (* style.scale raw))

(fn each-glyph [codepoints style iter]
  (each [i codepoint (ipairs codepoints)]
    (local glyph (fallback-glyph style.font codepoint))
    (iter i codepoint glyph (* glyph.advance style.scale))))

(fn measure-codepoints-width [codepoints style]
  (var width 0.0)
  (each [_ codepoint (ipairs codepoints)]
    (set width (+ width (glyph-advance style codepoint))))
  width)

(fn line-break? [codepoint]
  (or (= codepoint newline-codepoint)
      (= codepoint carriage-return-codepoint)))

(fn measure-text [layout codepoints style]
  (set layout.measure (glm.vec3 0))
  (var current-width 0.0)
  (var max-width 0.0)
  (var line-count 1)
  (var i 1)
  (local total (# codepoints))
  (while (<= i total)
    (local codepoint (. codepoints i))
    (if (line-break? codepoint)
        (do
          (set max-width (math.max max-width current-width))
          (set current-width 0.0)
          (set line-count (+ line-count 1))
          (when (and (= codepoint carriage-return-codepoint)
                     (< i total)
                     (= (. codepoints (+ i 1)) newline-codepoint))
            (set i (+ i 1))))
        (set current-width (+ current-width (glyph-advance style codepoint))))
    (set i (+ i 1)))
  (set max-width (math.max max-width current-width))
  (set (. layout.measure 1) max-width)
  (set (. layout.measure 2) (* (line-height style) line-count))
  layout.measure)

(fn measure-single-line [layout codepoints style]
  (measure-text layout codepoints style))

(fn codepoints-from-text [text]
  (if text
      (icollect [_ codepoint (utf8.codes text)] codepoint)
      []))

(fn copy-codepoints [codepoint-list]
  (if codepoint-list
      (icollect [_ codepoint (ipairs codepoint-list)] codepoint)
      []))

(fn wrap-break? [codepoint]
  (or (= codepoint (string.byte " "))
      (= codepoint (string.byte "\t"))))

(fn line-state-from [out start-index style]
  (var width 0.0)
  (var last-break-index nil)
  (for [i start-index (length out)]
    (local codepoint (. out i))
    (when (not (line-break? codepoint))
      (set width (+ width (glyph-advance style codepoint)))
      (when (wrap-break? codepoint)
        (set last-break-index i))))
  (values width last-break-index))

(fn insert-soft-break [out]
  (table.insert out newline-codepoint)
  (+ (length out) 1))

(fn wrap-codepoints-for-width [codepoints style max-width]
  (if (not (finite-number? max-width))
      (copy-codepoints codepoints)
      (do
        (local out [])
        (var line-width 0.0)
        (var line-start-index 1)
        (var last-break-index nil)
        (var i 1)
        (local total (length codepoints))
        (while (<= i total)
          (local codepoint (. codepoints i))
          (if (line-break? codepoint)
              (do
                (table.insert out newline-codepoint)
                (set line-width 0.0)
                (set line-start-index (+ (length out) 1))
                (set last-break-index nil)
                (when (and (= codepoint carriage-return-codepoint)
                           (< i total)
                           (= (. codepoints (+ i 1)) newline-codepoint))
                  (set i (+ i 1))))
              (do
                (local advance (glyph-advance style codepoint))
                (when (and (> line-width 0)
                           (> (+ line-width advance) max-width))
                  (if (and last-break-index
                           (>= last-break-index line-start-index))
                      (do
                        (tset out last-break-index newline-codepoint)
                        (set line-start-index (+ last-break-index 1))
                        (local (next-width next-break-index)
                          (line-state-from out line-start-index style))
                        (set line-width next-width)
                        (set last-break-index next-break-index))
                      (do
                        (set line-start-index (insert-soft-break out))
                        (set line-width 0.0)
                        (set last-break-index nil)))
                  (when (and (> line-width 0)
                             (> (+ line-width advance) max-width))
                    (set line-start-index (insert-soft-break out))
                    (set line-width 0.0)
                    (set last-break-index nil)))
                (table.insert out codepoint)
                (set line-width (+ line-width advance))
                (when (wrap-break? codepoint)
                  (set last-break-index (length out)))))
          (set i (+ i 1)))
        out)))

{: get-theme-text-color
 : resolve-style
 : fallback-glyph
 : glyph-advance
 : each-glyph
 : measure-codepoints-width
 : wrap-codepoints-for-width
 : measure-text
 : measure-single-line
 : codepoints-from-text
 : copy-codepoints
 : line-height
 : line-break?
 : newline-codepoint
 : carriage-return-codepoint}
