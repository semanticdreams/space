class BoolEntityView:
    def __init__(self, entity, focus_parent=None):
        self.focus = (focus_parent or world.focus).add_child(self)
        self.entity = entity

        self.actions_panel = z.ActionsPanel([
            ('copy entity', self.entity.copy),
        ], focus_parent=self.focus)

        self.toggle = z.ToggleSwitch(checked=self.entity.get_value(), focus_parent=self.focus)
        self.toggle.toggled.connect(self.on_toggle)

        self.column = z.Flex([
            z.FlexChild(self.actions_panel.layout),
            z.FlexChild(self.toggle.layout, flex=1)
        ], axis='y', xalign='largest')

        self.layout = self.column.layout

    def __str__(self):
        return str(self.entity)

    def on_toggle(self, checked):
        self.entity.set_value(checked)

    def drop(self):
        self.column.drop()
        self.actions_panel.drop()
        self.toggle.drop()
        self.focus.drop()

