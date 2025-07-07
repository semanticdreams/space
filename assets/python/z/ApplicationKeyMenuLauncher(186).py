class ApplicationKeyMenuLauncher:
    def  __init__(self):
        world.vim.modes['normal'].add_action_group(z.VimActionGroup('menu', [
            #z.VimAction('menu', self.launch_menu, sdl2.SDLK_APPLICATION),
            z.VimAction('menu', self.launch_menu, sdl2.SDLK_BACKSLASH),
        ]))

    def launch_menu(self):
        if world.focus.current is None:
            world.apps['Menus'].root.show(position=world.camera.camera.get_ahead_position(200))

    def drop(self):
        world.vim.modes['normal'].remove_action_group('menu')
