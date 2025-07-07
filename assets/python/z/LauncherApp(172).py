class LauncherApp:
    def __init__(self):
        world.vim.modes['leader'].add_action_group(z.VimActionGroup('launcher', [
            z.VimAction('launcher', self.open_launcher, sdl2.SDLK_p),
            z.VimAction('kill', self.kill_floatie, sdl2.SDLK_x),
            z.VimAction('kill all', self.kill_all_floaties, sdl2.SDLK_DELETE),
        ]))

    def open_launcher(self):
        launcher_view = world.classes['LauncherView']()
        world.floaties.add(launcher_view)
        world.vim.set_current_mode('normal')
        world.vim._ignore_next_char = True

    def kill_floatie(self):
        world.vim.set_current_mode('normal')
        #world.floaties.floaties_indicator.kill_triggered()
        current_root_children = [x for x in world.floaties.floaties.keys()
                                 if x.focus.has_current_descendant()]
        if current_root_children:
            world.floaties.drop_obj(one(current_root_children))

    def kill_all_floaties(self):
        world.floaties.drop_all()

    def drop(self):
        pass
