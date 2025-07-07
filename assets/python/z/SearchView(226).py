class SearchView:
    def __init__(self, items=None, builder=None, focus_parent=None, name='search-view', show_head=False,
                 num_per_page=10):
        self.show_head = show_head
        self.items = sorted(items, key=lambda x: x[1])
        self.submitted = z.Signal()
        self.query = ''
        self.focus = (focus_parent or world.focus).add_child(obj=self)
        self.input = z.Input(focus_parent=self.focus)
        self.input.submitted.connect(self.on_input_submitted)
        self.input.changed.connect(self.on_input_changed)

        self.builder = builder or self.default_list_view_item_builder

        if self.show_head:
            self.head = z.ContextButton(label=name, focus_parent=self.focus,
                                                color=(1, 0.5, 1, 1), focusable=False)

        self.list_view = z.ListView(self.items, self.builder,
                                            num_per_page=num_per_page,
                                            focus_parent=self.focus,
                                            show_head=False)

        row_objs = [z.FlexChild(self.input.layout),
                    z.FlexChild(self.list_view.layout, flex=1)]
        if self.show_head:
            row_objs.insert(0, z.FlexChild(self.head.layout))
        self.row = z.Flex(row_objs, axis='y', xalign='largest')

        self.layout = self.row.layout
        if self.show_head:
            self.spatiolator = z.Spatiolator(self.layout,
                                                          self.head.spatiolator.handle)

    def set_hud(self, hud):
        self.input.set_hud(hud)
        self.list_view.set_hud(hud)
        if self.head:
            self.head.set_hud(hud)

    def default_list_view_item_builder(self, item, context=None):
        #b = z.Button(item[1], focus_parent=context['focus_parent'], on_click=lambda p, r, i, item=item: self.submitted.emit(item))
        b = z.ContextButton(label=item[1], focus_parent=context['focus_parent'], actions=[
            ('submit', lambda: self.submitted.emit(item))
        ])
        return b

    def set_items(self, items):
        self.items = items
        self.update_list_view()

    def update_list_view(self):
        self.list_view.set_items([x for x in self.items if util.fuzzy_match(self.query, x[1])])

    def on_input_changed(self, value):
        self.query = value
        self.update_list_view()

    def on_input_submitted(self):
        pass

    def drop(self):
        if self.focus:
            self.focus.disconnect()
        self.row.drop()
        if self.show_head:
            self.head.drop()
        self.list_view.drop()
        self.input.drop()
        self.focus.drop()
