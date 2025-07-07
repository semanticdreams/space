class VimMode:
    def __init__(self, name):
        self.name = name
        self.action_groups = {}
        self._key_map = {}

    def _update_key_map(self):
        self._key_map.clear()
        for name, action_group in self.action_groups.items():
            for action in action_group.actions:
                self._key_map[action.key] = action
        world.vim.current_mode_changed.emit()

    def on_enter(self):
        pass

    def on_leave(self):
        pass

    def add_action_group(self, action_group):
        self.action_groups[action_group.name] = action_group
        self._update_key_map()

    def remove_action_group(self, name):
        del self.action_groups[name]
        self._update_key_map()

    def on_character(self, key):
        pass

    def on_keyboard(self, key, scancode, action, mods):
        mod_keys = (
            sdl2.SDLK_LCTRL,
            sdl2.SDLK_RCTRL,
            sdl2.SDLK_LSHIFT,
            sdl2.SDLK_RSHIFT,
            sdl2.SDLK_LALT,
            sdl2.SDLK_RALT,
            sdl2.SDLK_LGUI,   # Left "Windows" / "Command" key
            sdl2.SDLK_RGUI,   # Right "Windows" / "Command" key
            sdl2.SDLK_MODE    # AltGr (if used)
        )
        if action == 1 and (mods == 0 or key in mod_keys):
            if key in self._key_map:
                self._key_map[key].func()

    def on_controller_button_down(self, button):
        pass

    def on_controller_button_up(self, button):
        pass

    def on_controller_motion(self, axis, value):
        pass
