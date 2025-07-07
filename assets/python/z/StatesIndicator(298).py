class StatesIndicator:
    def __init__(self):
        self.state_label = z.ContextButton(
            hud=True,
            focusable=False,
            label='state: ' + world.states.get_status(), color=world.themes.theme.red[500],
            foreground_color=world.themes.theme.gray[900]
        )
        world.states.changed.connect(self.state_changed)
        world.apps['Hud'].top_panel.add(self.state_label)

    def state_changed(self):
        self.state_label.set_label('state: ' + world.states.get_status())

    def drop(self):
        world.apps['Hud'].top_panel.remove(self.state_label)
        self.state_label.drop()