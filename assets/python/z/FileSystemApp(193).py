class FileSystemApp:
    def __init__(self):
        world.vim.modes['apps'].add_action_group(
            z.VimActionGroup('fs', [
                z.VimAction('fs', self.open_fs, sdl2.SDLK_f),
            ]))

    def open_fs(self):
        world.vim.set_current_mode('normal')
        world.floaties.add(world.classes['FileSystemView']())

    def drop(self):
        world.vim.modes['apps'].remove_action_group('fs')