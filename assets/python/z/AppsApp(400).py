class AppsApp:
    def __init__(self):
        self.apps_browser = None
        self.hud_button = z.ContextButton(label='0', color=(1, 0, 0.4, 0.9), actions=[
            ('open', self.open_apps_browser),
            ('reload', world.apps.reload),
        ], focusable=False, hud=True)
        world.apps['Hud'].top_panel.add(self.hud_button)

        world.vim.modes['normal'].add_action_group(z.VimActionGroup('apps', [
            z.VimAction('open-apps-browser', self.open_apps_browser, sdl2.SDLK_m),
        ]))

        world.apps.apps_changed.connect(self.on_apps_changed)

    def on_apps_changed(self):
        self.update_hud_button()

    def update_hud_button(self):
        self.hud_button.set_label(f'{len(world.apps.names)}')

    def open_apps_browser(self):
        self.apps_browser = z.AppsBrowser(world.apps)
        world.floaties.add(self.apps_browser)
        world.vim.set_current_mode('normal')

    def drop(self):
        pass
