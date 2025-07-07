class ClaudeIndicator:
    def __init__(self):
        self.label = z.ContextButton(
            hud=True,
            focusable=False,
            label='claude',
            actions=[
                ('open', lambda: world.floaties.add(z.ClaudeView())),
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)

    def drop(self):
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()
