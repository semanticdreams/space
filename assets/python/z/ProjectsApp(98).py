class ProjectsApp:
    def __init__(self):
        world.vim.modes['apps'].add_action_group(z.VimActionGroup('projects', [
            z.VimAction('projects', self.open_projects, sdl2.SDLK_p),
        ]))

    def open_projects(self):
        world.floaties.add(world.classes.get_class(name='ProjectsView')())
        world.vim.set_current_mode('normal')
        world.vim._ignore_next_char = True

    def drop(self):
        world.vim.modes['apps'].remove_action_group('projects')