class ListEntityViewChild:
    def __init__(self, list_entity_view, entity, focus_parent=None):
        self.focus = focus_parent.add_child(self)
        self.list_entity_view = list_entity_view
        self.entity = entity
        assert isinstance(self.entity.id, str)
        #tags = z.TagEntity.get_tags_for_entity(self.entity.id)
        #tag_names = [x.tag for x in tags]
        tag_str = ''#', '.join(tag_names)
        self.tags_label = z.Label(
            tag_str,
            padding_insets=(0.2, 0.2),
            text_style=z.TextStyle(scale=1.5,
                                   font=world.themes.theme.italic_font,
                                   color=world.themes.theme.grey[500]))

        self.obj = self.entity.preview(self.entity, focus_parent=self.focus)
        self.menu_button = z.Button('icon:more_vert', focus_parent=self.focus)
        self.menu_button.clicked.connect(self.menu_triggered)

        self.column = z.Flex([
            z.FlexChild(self.tags_label.layout),
            z.FlexChild(self.obj.layout, flex=1),
        ], axis='y', xalign='largest')

        self.row = z.Flex([
            z.FlexChild(self.column.layout, flex=1),
            z.FlexChild(self.menu_button.layout),
        ], yalign='largest')

        self.card = z.Card(self.row.layout)

        self.layout = self.card.layout

    def menu_triggered(self, f, i, d):
        actions = [
            ('up', self.move_up),
            ('down', self.move_down),
            ('remove', self.remove_item_from_list),
        ]
        world.apps['Menus'].create_menu(
            actions, focus_parent=self.focus,
            position=self.menu_button.layout.position + np.array((0, 0, 0.1))
        ).show()

    def move_up(self):
        self.list_entity_view.move_item_up(self.entity)

    def move_down(self):
        self.list_entity_view.move_item_down(self.entity)

    def remove_item_from_list(self):
        self.list_entity_view.remove_item(self.entity)

    def drop(self):
        self.card.drop()
        self.column.drop()
        self.tags_label.drop()
        self.row.drop()
        self.menu_button.drop()
        self.obj.drop()
        self.focus.drop()
