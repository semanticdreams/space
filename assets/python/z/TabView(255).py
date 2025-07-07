class TabView:
    def __init__(self, items, focus_parent=None, horizontal=False,
                 initial_tab=0):
        self.focus = focus_parent.add_child(self)
        self.items = items
        self.current_tab = None
        self.current_tab_idx = None
        self.buttons = [z.Button(name, focus_parent=self.focus, centered=False,
                               on_click=lambda f, i_, d, i=i: self.set_current_tab(i))
                        for i, (name, builder) in enumerate(self.items)]
        self.button_row = z.Flex([z.FlexChild(x.layout) for x in self.buttons],
                               xspacing=0.1 if horizontal else 0.0,
                               yspacing=0.1 if not horizontal else 0.0,
                               axis='x' if horizontal else 'y',
                               yalign='largest' if horizontal else 'start',
                               xalign='largest' if not horizontal else 'start')
        self.column = z.Flex([z.FlexChild(self.button_row.layout)],
                           axis='y' if horizontal else 'x',
                           xalign='largest' if horizontal else 'start',
                           yspacing=0.1 if horizontal else 0.0,
                           yalign='largest' if not horizontal else 'start',
                           xspacing=0.1 if not horizontal else 0.0)
        self.layout = self.column.layout
        if self.items:
            self.set_current_tab(initial_tab)

    def set_current_tab(self, idx):
        if idx < 0:
            idx = len(self.items) + idx
        self.column.clear_children()
        if self.current_tab is not None:
            self.current_tab.drop()
        context = {
            'focus_parent': self.focus
        }
        self.current_tab_idx = idx
        self.current_tab = self.items[idx][1](context)
        self.column.set_children([z.FlexChild(self.button_row.layout), z.FlexChild(self.current_tab.layout, flex=1)])
        self.layout.mark_measure_dirty()

    def reload_current_tab(self):
        self.set_current_tab(self.current_tab_idx)

    def drop(self):
        self.column.drop()
        if self.current_tab:
            self.current_tab.drop()
        self.button_row.drop()
        [x.drop() for x in self.buttons]
        self.focus.drop()