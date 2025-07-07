class TreeViewRow:
    def __init__(self, tree_view, item, item_obj):
        self.tree_view = tree_view
        self.item = item
        self.item_obj = item_obj
        self.expand_button = z.Button(
            'icon:keyboard_arrow_' + ('down' if item.expanded else 'right'),
            background_color=world.themes.theme.dialog_background_color,
            #padding_insets=(0.5, 0.3),
            focusable=False
        )
        self.expand_button.clicked.connect(self.on_expand_clicked)
        self.row = z.Flex([
            z.FlexChild(self.expand_button.layout),
            z.FlexChild(self.item_obj.layout, flex=1)
        ], yalign='largest')
        self.layout = self.row.layout

    def on_expand_clicked(self, f, i, d):
        self.item.expanded = not self.item.expanded
        self.tree_view.update_items()

    def drop(self):
        self.row.drop()
        self.item_obj.drop()
        self.expand_button.drop()
