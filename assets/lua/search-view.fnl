(local Input (require :input))
(local ListView (require :list-view))
(local {: Flex : FlexChild} (require :flex))
(local Signal (require :signal))
(local Button (require :button))
(local StringUtils (require :string-utils))

(fn normalize-items [items]
    (local copy [])
    (each [_ pair (ipairs (or items []))]
        (when pair
            (table.insert copy pair)))
    (table.sort copy
                (fn [a b]
                    (local la (tostring (. a 2)))
                    (local lb (tostring (. b 2)))
                    (< la lb)))
    copy)

(local fuzzy-match StringUtils.fuzzy-match)

(fn default-item-builder [search item ctx]
    (local label (tostring (. item 2)))
    (local button
        ((Button {:text label
                  :variant :ghost
                  :on-click (fn [_button _event]
                              (search.submitted:emit item))})
         ctx))
    button)

(fn SearchView [opts]
    (local options (or opts {}))
    (local items (normalize-items options.items))
    (local name (or options.name "search-view"))
    (local items-per-page (or options.num-per-page options.items-per-page 10))

    (fn build [ctx]
        (local search-view {:ctx ctx
                            :items items
                            :query ""
                            :submitted (Signal)})
        (local input
            ((Input {:text (or options.text "")
                     :placeholder (or options.placeholder "Search")})
             ctx))
        (local item-builder
            (or options.builder
                (fn [item child-ctx]
                    (default-item-builder search-view item child-ctx))))
        (local list-view
            ((ListView {:items search-view.items
                        :builder item-builder
                        :name name
                        :show-head (or options.show-head false)
                        :paginate false
                        :fill-width true
                        :items-per-page items-per-page
                        :scroll true
                        :scrollbar-policy (or options.scrollbar-policy :as-needed)})
             ctx))

        (set search-view.input input)
        (set search-view.list-view list-view)

        (local flex
            ((Flex {:axis 2
                    :xalign :stretch
                    :children [(FlexChild (fn [_] input) 0)
                               (FlexChild (fn [_] list-view) 1)]})
             ctx))

        (fn set-items [self new-items]
            (set self.items (normalize-items new-items))
            (self:update-list-view))

        (fn filter-items [self]
            (icollect [_ pair (ipairs self.items)]
                (when (fuzzy-match self.query (tostring (. pair 2)))
                    pair)))

        (fn update-list-view [self]
            (local filtered (self:filter-items))
            (self.list-view:set-items filtered))

        (fn on-input-changed [value]
            (set search-view.query (or value ""))
            (search-view:update-list-view))

        (set search-view.set-items set-items)
        (set search-view.filter-items filter-items)
        (set search-view.update-list-view update-list-view)

        (set search-view.layout flex.layout)
        (set search-view.drop
            (fn [self]
                (when self.__input-listener
                    (self.input.model.changed:disconnect self.__input-listener true)
                    (set self.__input-listener nil))
                (self.list-view:drop)
                (self.input:drop)
                (self.layout:drop)))

        (set search-view.__input-listener
            (input.model.changed:connect
                (fn [text]
                    (on-input-changed text))))

        (search-view:update-list-view)
        search-view))

SearchView
