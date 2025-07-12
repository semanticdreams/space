class FSFolderEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.entity.delete),
        ], focus_parent=self.focus)

        val = self.entity.get_path()
        self.base_input = z.Input('' if self.entity.base is None else self.entity.base,
                                  focus_parent=self.focus)
        self.base_input.submitted.connect(self.on_base_input_submitted)

        self.input = z.Input('' if val is None else val, focus_parent=self.focus)
        self.input.submitted.connect(self.on_input_submitted)

        self.list_view = z.ListView(builder=self.list_view_builder,
                                    focus_parent=self.focus)

        self.row = z.Flex([
            z.FlexChild(self.base_input.layout),
            z.FlexChild(self.input.layout),
        ], yalign='largest')

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.row.layout),
            z.FlexChild(self.list_view.layout, flex=1),
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

        self.update_items()

    def list_view_builder(self, item, context):
        return z.ContextButton(
            label=item,
            focus_parent=context['focus_parent'],
            actions=[
                ('edit', lambda: world.floaties.add(
                    z.Editor(os.path.join(self.entity.get_full_path(), item)))),
            ]
        )

    def update_items(self):
        path = self.entity.get_full_path()
        names = os.listdir(path)
        self.list_view.set_items(names)

    def __str__(self):
        return str(self.entity)

    def on_input_submitted(self):
        val = self.input.text or None
        self.entity.set_path(val)
        self.input.set_text('' if val is None else val)
        self.update_items()

    def on_base_input_submitted(self):
        val = self.base_input.text
        self.entity.set_base(val if val else None)
        self.update_items()

    def drop(self):
        self.column.drop()
        self.row.drop()
        self.list_view.drop()
        self.actions_panel.drop()
        self.base_input.drop()
        self.input.drop()
        self.focus.drop()

