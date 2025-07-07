class TableView:
    def __init__(self, items):
        self.items = items
        self.keys = list(items[0].keys())
        self.key_buttons = [z.ContextButton(label=key, color=[0.8, 0.8, 0.3, 1]) for key in self.keys]
        self.item_buttons = []
        self.grid = z.Grid()
        self.pagination = z.Pagination(len(items))
        self.pagination.page_changed.connect(self.page_changed)
        self.column = z.Flex([self.grid, self.pagination], axis='y', xalign='largest')
        self.add_key_buttons_to_grid()
        self.layout = self.column.layout
        self.spatiolator = z.Spatiolator(self.layout, self.key_buttons[0])
        self.focus = world.focus.add_child(self)
        return self.pagination.set_page(0)

    def add_key_buttons_to_grid(self):
        return [self.grid.add_widget(x, [i, 0, 0]) for [i, x] in enumerate(self.key_buttons)]

    def drop_item_buttons(self):
        for button in self.item_buttons:
            button.drop()
        return self.item_buttons.clear()

    def drop_key_buttons(self):
        for button in self.key_buttons:
            button.drop()
        return self.key_buttons.clear()

    def page_changed(self, data):
        self.grid.clear()
        self.drop_item_buttons()
        self.add_key_buttons_to_grid()
        [start, stop] = data['slice']
        page_items = self.items[start:stop:None]
        for [i, item] in enumerate(page_items):
            for [j, key] in enumerate(self.keys):
                button = z.ContextButton(label=str(item[key]), color=[0.9, 0.9, 0.4, 1])
                self.item_buttons.append(button)
                self.grid.add_widget(button, [j, i + 1, 0])

    def drop(self):
        self.column.drop()
        self.grid.drop()
        self.drop_item_buttons()
        self.drop_key_buttons()
        return self.pagination.drop()