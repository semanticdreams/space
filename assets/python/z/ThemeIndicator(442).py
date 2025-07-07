class ThemeIndicator:
    def __init__(self):
        self.label = z.ContextButton(hud=True,
            focusable=False,
            label='theme',
            color=world.themes.theme.yellow[800],
            actions=[
                ('cycle', self.cycle_triggered),
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)

    def cycle_triggered(self):
        world.themes.cycle_theme()

    def drop(self):
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()