(local Harness (require :tests.e2e.harness))
(local glm (require :glm))
(local TabView (require :tab-view))
(local Card (require :card))
(local Padding (require :padding))
(local Sized (require :sized))
(local Rectangle (require :rectangle))
(local Text (require :text))
(local TextStyle (require :text-style))
(local {: Flex : FlexChild} (require :flex))

(fn make-panel [label accent-color]
  (fn [ctx]
    (local theme (and ctx ctx.theme))
    (local text-color (and theme theme.text theme.text.foreground))
    (assert text-color "tab-view snapshot requires theme text color")
    (local title-style (TextStyle {:scale 2.0 :color text-color :bold? true}))
    (local body-style (TextStyle {:scale 1.6 :color text-color}))
    ((Card
       {:child
        (Padding
          {:edge-insets [0.9 0.7]
	           :child
	           (Flex {:axis 2
	                  :reverse true
	                  :yspacing 0.5
	                  :xalign :start
	                  :children
	                  [(FlexChild (Text {:text label
	                                     :style title-style}) 0)
	                   (FlexChild
	                     (Text {:text "Tab content area"
	                            :style body-style}) 0)
	                   (FlexChild
	                     (Sized {:size (glm.vec3 7.0 2.8 0)
	                             :child (Rectangle {:color accent-color})})
	                     0)
	                   ]})})})
     ctx)))

(fn make-tab-view [opts]
  (local options (or opts {}))
  (TabView
    {:horizontal? (or options.horizontal? false)
     :initial-tab (or options.initial-tab 1)
     :tab-spacing 0.25
     :content-spacing 0.35
     :tab-padding [0.55 0.35]
     :active-variant :primary
     :inactive-variant :ghost
     :items
     [["Alpha" (make-panel "Alpha Panel" (glm.vec4 0.25 0.43 0.96 1))]
      ["Beta" (make-panel "Beta Panel" (glm.vec4 0.17 0.55 0.36 1))]
      ["Gamma" (make-panel "Gamma Panel" (glm.vec4 0.85 0.57 0.21 1))]]}))

(fn make-root-builder []
	(fn [ctx]
	    (local left-builder
	      (Sized {:size (glm.vec3 25.0 18.0 0)
	              :child (make-tab-view {:horizontal? false
	                                     :initial-tab 1})}))
	    (local right-builder
	      (Sized {:size (glm.vec3 25.0 18.0 0)
	              :child (make-tab-view {:horizontal? true
	                                     :initial-tab 2})}))
	    ((Sized
	       {:size (glm.vec3 58.0 24.0 0)
	        :child
	        (Card
	          {:child
	           (Padding
	             {:edge-insets [1.3 1.0]
	              :child
	              (Flex {:axis :x
	                     :xspacing 1.6
	                     :yalign :stretch
	                     :children [(FlexChild left-builder 1)
	                                (FlexChild right-builder 1)]})})})})
	     ctx)))

(fn run [ctx]
  (local target
    (Harness.make-screen-target {:width ctx.width
                                 :height ctx.height
                                 :world-units-per-pixel ctx.units-per-pixel
                                 :builder (make-root-builder)}))
  (Harness.draw-targets ctx.width ctx.height [{:target target}])
  (Harness.capture-snapshot {:name "tab-view"
                             :width ctx.width
                             :height ctx.height
                             :tolerance 2})
  (Harness.cleanup-target target))

(fn main []
  (Harness.with-app {:width 1280
                     :height 720
                     :units-per-pixel 0.05}
                   (fn [ctx]
                     (run ctx)))
  (print "E2E tab-view snapshot complete"))

{:run run
 :main main}
