class ConsoleView:
    def __init__(self, console):
        self.console = console
        #self.console_view_vim_mode = z.ConsoleViewVimMode(self)
        self.focus = world.focus.add_child(obj=self, on_subtree_changed=self.on_focus_changed)

        self.output = z.Input(focus_parent=self.focus, multiline=True, max_lines=30, min_lines=20)
        self.input = z.Input(focus_parent=self.focus, multiline=True, max_lines=3, min_lines=3)
        self.input.submitted.connect(self.input_submitted)
        self.column = z.Flex([z.FlexChild(self.output.layout),
                              z.FlexChild(self.input.layout),],
                             axis='y', xalign='largest')

        self.layout = self.column.layout

        self.update()

        self.console.changed.connect(self.update)

    def on_focus_changed(self, focused):
        pass
        #if focused:
        #    world.vim.add_mode(self.console_view_vim_mode)
        #    world.vim.modes['normal'].add_action_group(z.VimActionGroup('console', [
        #        z.VimAction('console', self.set_console_vim_mode, sdl2.SDLK_i),
        #    ]))
        #else:
        #    world.vim.modes['normal'].remove_action_group('console')
        #    world.vim.remove_mode('console')

    #def set_console_vim_mode(self):
    #    world.vim._ignore_next_char = True
    #    world.vim.set_current_mode('console')

    def input_submitted(self):
        self.console.write(self.input.text)
        self.console.ret()
        self.input.set_text('')

    def update(self):
        text = '\n'.join(self.console.cmdlines[-300:])
        text = textwrap.fill(text, tabsize=4, replace_whitespace=False, drop_whitespace=False)
        text = '\n'.join(text.split('\n')[-100:])
        self.output.set_text(text)

    def drop(self):
        #world.vim.set_current_mode('normal')
        self.console.changed.disconnect(self.update)
        self.column.drop()
        self.input.drop()
        self.output.drop()
        self.focus.drop()