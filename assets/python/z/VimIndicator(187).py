from collections import defaultdict
class VimIndicator:
    def __init__(self):
        if world.states.is_state_active(world.vim.state):
            self.vim_state_entered()
        world.vim.entered.connect(self.vim_state_entered)
        world.vim.left.connect(self.vim_state_left)

    def vim_state_entered(self):
        self.label = z.Label(hud=True, color=world.themes.theme.grey[900])
        world.apps['Hud'].bottom_panel.add(self.label)
        self.current_vim_changed()
        world.vim.current_mode_changed.connect(self.current_vim_changed)

    def vim_state_left(self):
        world.vim.current_mode_changed.disconnect(self.current_vim_changed)
        world.apps['Hud'].bottom_panel.remove(self.label)
        self.label.drop()

    def current_vim_changed(self):
        mode = world.vim.current_mode
        info = defaultdict(dict)
        actions = [y for x in mode.action_groups.values() for y in x.actions]
        entries = [f'[{chr(x.key if x.key < 0x110000 else 32)}] {x.name}' for x in actions]
        width = max((len(x) for x in entries)) if entries else 0
        text = ' '.join((f'{x:<{1 + width}}' for x in entries))
        self.label.text.set(text)

    def drop(self):
        pass
