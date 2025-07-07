class SpeechRecorderIndicator:
    def __init__(self):
        self.label = z.ContextButton(hud=True,
            focusable=False,
            label='sr',
            color=world.themes.theme.green[800],
            actions=[
                ('rec', self.rec),
            ]
        )
        world.apps['Hud'].top_panel.add(self.label)

        world.vim.modes['normal'].add_action_group(z.VimActionGroup('sr', [
            z.VimAction('rec', self.rec, sdl2.SDLK_RCTRL),
        ]))

    def rec(self):
        prev_color = self.label.color
        self.label.set_color((1, 0.1, 0.3, 1))
        def f():
            result = world.apps.ensure_app('SpeechRecorder').listen_and_recognize()
            print(result)
            self.label.set_color(prev_color)
        world.next_tick(f)

    def drop(self):
        world.vim.modes['normal'].remove_action_group('sr')
        world.apps['Hud'].top_panel.remove(self.label)
        self.label.drop()
