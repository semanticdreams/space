class JsonEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
            ('delete', self.entity.delete),
        ], focus_parent=self.focus)

        val = json.dumps(self.entity.get_data(), indent=2)
        self.input = z.Input(val, focus_parent=self.focus, multiline=True)
        self.input.submitted.connect(self.on_input_submitted)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.input.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def on_input_submitted(self):
        val = json.loads(self.input.text)
        self.entity.set_data(val)
        self.input.set_text(json.dumps(val, indent=2) if val is not None else '')

    def __str__(self):
        return str(self.entity)

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.input.drop()
        self.focus.drop()

