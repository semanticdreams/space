class VimView:
    def __init__(self):
        self.focus = world.focus.add_child(self)
        items = [(k, lambda ctx, v=v: self.tab_builder(v, ctx))
                 for k, v in world.vim.modes.items()]
        self.tab_view = z.TabView(items, focus_parent=self.focus)
        self.layout = self.tab_view.layout

    def tab_builder(self, mode, ctx):
        text = '\n'.join((k + ': ' + ', '.join((x.name + f' ({x.key})' for x in v.actions))
                            for k, v in mode.action_groups.items()))
        return z.Label(text)

    def drop(self):
        self.tab_view.drop()
        self.focus.drop()
