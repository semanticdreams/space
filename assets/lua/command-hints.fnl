(local SDLK_ESCAPE 27)
(local SDLK_RETURN 13)
(local SDLK_DELETE 127)
(local SDLK_BACKSPACE 8)
(local SDLK_TAB 9)
(local SDLK_SPACE 32)
(local SDLK_LEFT 1073741904)
(local SDLK_RIGHT 1073741903)
(local SDLK_UP 1073741906)
(local SDLK_DOWN 1073741905)
(local SDLK_F1 1073741882)
(local SDLK_F12 1073741893)

(fn entry [key label opts]
  (local options (or opts {}))
  {:key key
   :label label
   :priority (or options.priority 50)
   :show-collapsed? (if (= options.show-collapsed? nil) true options.show-collapsed?)
   :id options.id})

(fn section [id title entries]
  {:id id
   :title title
   :entries entries})

(fn key-label [value]
  (if (= value nil)
      ""
      (= (type value) :string)
      value
      (= value SDLK_ESCAPE)
      "esc"
      (= value SDLK_RETURN)
      "enter"
      (= value SDLK_DELETE)
      "del"
      (= value SDLK_BACKSPACE)
      "backspace"
      (= value SDLK_TAB)
      "tab"
      (= value SDLK_SPACE)
      "space"
      (= value SDLK_LEFT)
      "left"
      (= value SDLK_RIGHT)
      "right"
      (= value SDLK_UP)
      "up"
      (= value SDLK_DOWN)
      "down"
      (and (= (type value) :number)
           (>= value SDLK_F1)
           (<= value SDLK_F12))
      (.. "f" (+ 1 (- value SDLK_F1)))
      (and (= (type value) :number)
           (>= value 32)
           (< value 127))
      (string.char value)
      (string.lower (tostring value))))

{:entry entry
 :section section
 :key-label key-label
 :KEY_F1 SDLK_F1}
