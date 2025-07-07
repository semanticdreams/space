class FocusIndicator:
    def __init__(self):
        self.focus_label = z.ContextButton(label=' '*30, color=world.themes.theme.yellow[700],
                                                   foreground_color=world.themes.theme.grey[900],
                                                   focusable=False,
                                                  hud=True)
        world.apps['Time'].set_interval(self.update_focus, 2000)
        world.apps['Hud'].top_panel.add(self.focus_label)

    def update_focus(self):
        n = world.focus.current
        nodes = []
        while n:
            nodes.append(n)
            n = n.parent
        text = ' / '.join((str(x.obj.__class__.__name__) for x in reversed(nodes)))
        self.focus_label.set_label(f'{text[-30:]:<30}')

    def drop(self):
        pass
