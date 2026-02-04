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
        (let [glyph (fallback-glyph style.font codepoint)]
          (set current-width (+ current-width (* glyph.advance style.scale)))))
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

{: get-theme-text-color
 : resolve-style
 : fallback-glyph
 : each-glyph
 : measure-text
 : measure-single-line
 : codepoints-from-text
 : copy-codepoints
 : line-height
 : line-break?
 : newline-codepoint
 : carriage-return-codepoint}
