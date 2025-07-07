class DictEntityViewChild:
    def __init__(self, view, key_entity, value_entity, focus_parent=None):
        self.focus = focus_parent.add_child(self)
        self.view = view
        self.key_entity = key_entity
        self.value_entity = value_entity

        self.key_obj = self.key_entity.preview(self.key_entity, focus_parent=self.focus)
        self.value_obj = (
            self.value_entity.preview(self.value_entity, focus_parent=self.focus)
            if self.value_entity else z.Label('<no value>')
        )

        self.menu_button = z.Button('icon:more_vert', focus_parent=self.focus)
        self.menu_button.clicked.connect(self.menu_triggered)

        self.arrow = z.Label('->')

        self.row = z.Flex([
            z.FlexChild(self.key_obj.layout),
            z.FlexChild(self.arrow.layout),
            z.FlexChild(self.value_obj.layout, flex=1),
            z.FlexChild(self.menu_button.layout)
        ], yalign='largest')

        self.layout = self.row.layout

    def menu_triggered(self, f, i, d):
        actions = [
            ('paste value entity', self.paste_value),
            ('remove pair', self.remove_pair)
        ]
        world.apps['Menus'].create_menu(
            actions, focus_parent=self.focus,
            position=self.menu_button.layout.position + np.array((0, 0, 0.1))
        ).show()

    def paste_value(self):
        assert Y.register_type == 'entity'
        value = Y.value
        self.view.set_pair_value(self.key_entity, value)

    def remove_pair(self):
        self.view.remove_pair(self.key_entity)

    def drop(self):
        self.row.drop()
        self.menu_button.drop()
        self.key_obj.drop()
        self.value_obj.drop()
        self.arrow.drop()
        self.focus.drop()
