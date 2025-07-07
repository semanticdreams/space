class WorldIndicator:
    def __init__(self):
        self.label = z.ContextButton(hud=True,
            focusable=False,
            label='world',
            color=world.themes.theme.green[800],
            actions=[
                ('inspect', self.inspect),
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)

        world.vim.modes['normal'].add_action_group(z.VimActionGroup('world', [
            z.VimAction('world', self.inspect, sdl2.SDLK_F12),
        ]))

    def inspect(self):
        world.floaties.add(z.PyObjView(world))

    def drop(self):
        world.vim.modes['normal'].remove_action_group('world')
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()
