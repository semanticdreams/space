class FoldersView:
    def __init__(self):
        self.name = z.ReactiveValue('folders')
        self.focus = world.focus.add_child(self)

        actions = [
            ('create', self.create_item),
            ('reload', self.load_items),
        ]
        self.actions_panel = z.ActionsPanel(actions, self.focus)
        self.search_view = z.SearchView(items=[], builder=self.search_view_item_builder,
                                                focus_parent=self.focus, show_head=False)
        self.column = z.Flex([z.FlexChild(self.actions_panel.layout),
                z.FlexChild(self.search_view.layout)], axis='y', xalign='largest')
        self.layout = self.column.layout

        self.load_items()

    def search_view_item_builder(self, item, context):
        b = z.ContextButton(label=item[1], focus_parent=context['focus_parent'], color=(0.4, 0.9, 0.4, 1),
                   actions=[
                       ('get', lambda: world.floaties.add(z.FolderView(item[0]))),
                   ])
        return b

    def load_items(self):
        self.items = world.folders.get_folders()
        self.items_updated()

    def items_updated(self):
        self.search_view.set_items([(x, x['name'] or '') for x in self.items])

    def create_item(self):
        folder = world.folders.create_folder()
        self.items.append(folder)
        self.items_updated()

    def drop(self):
        self.column.drop()
        self.search_view.drop()
        self.actions_panel.drop()
        self.focus.drop()