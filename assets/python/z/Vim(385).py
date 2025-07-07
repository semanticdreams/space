class Vim:
    def __init__(self):
        self.state = world.states.create_state(name='vim', on_enter=self.on_enter, on_leave=self.on_leave)
        self.entered = z.Signal()
        self.left = z.Signal()

        self._connected_gamepads = set()

        self.modes = {}
        self.current_mode_changed = z.Signal()

        self._ignore_next_char = False

        world.vim = self
        self.default_setup()

    def default_setup(self):
        self.add_mode(z.NormalVimMode())
        self.add_mode(z.InsertVimMode())
        self.add_mode(z.LeaderVimMode())
        self.add_mode(z.AppsVimMode())
        self.add_mode(z.QuitVimMode())
        self.add_mode(z.StateVimMode())
        self.add_mode(z.EntitiesVimMode())
        self.current_mode = self.modes['normal']

    def add_mode(self, mode):
        self.modes[mode.name] = mode

    def remove_mode(self, name):
        del self.modes[name]

    def set_current_mode(self, name):
        mode = self.modes[name]
        if mode != self.current_mode:
            if self.current_mode is not None:
                self.current_mode.on_leave()
            self.current_mode = mode
            self.current_mode.on_enter()
            self.current_mode_changed.emit()

    def on_enter(self):
        world.window.keyboard.connect(self.on_keyboard)
        world.window.character.connect(self.on_character)
        world.apps['CombinedMouseControl'].on_enter()
        world.gamepads.gamepad_added.connect(self.gamepad_added)
        world.gamepads.gamepad_removed.connect(self.gamepad_removed)
        for gamepad in world.gamepads.gamepads:
            self.gamepad_added(gamepad)
        self.entered.emit()

    def on_leave(self):
        world.window.keyboard.disconnect(self.on_keyboard)
        world.window.character.disconnect(self.on_character)
        world.apps['CombinedMouseControl'].on_leave()
        world.gamepads.gamepad_added.disconnect(self.gamepad_added)
        world.gamepads.gamepad_removed.disconnect(self.gamepad_removed)
        for gamepad in list(self._connected_gamepads):
            self.gamepad_removed(gamepad)
        self.left.emit()

    def gamepad_added(self, gamepad):
        if gamepad not in self._connected_gamepads:
            gamepad.button_down.connect(self.controller_button_down)
            gamepad.button_up.connect(self.controller_button_up)
            gamepad.motion.connect(self.controller_motion)
            self._connected_gamepads.add(gamepad)

    def gamepad_removed(self, gamepad):
        if gamepad in self._connected_gamepads:
            gamepad.button_down.disconnect(self.controller_button_down)
            gamepad.button_up.disconnect(self.controller_button_up)
            gamepad.motion.disconnect(self.controller_motion)
            self._connected_gamepads.discard(gamepad)

    def on_keyboard(self, key, scancode, action, mods):
        self.current_mode.on_keyboard(key, scancode, action, mods)

    def on_character(self, key):
        if self._ignore_next_char:
            self._ignore_next_char = False
        else:
            self.current_mode.on_character(key)

    def controller_button_down(self, button, state, timestamp):
        self.current_mode.on_controller_button_down(button)

    def controller_button_up(self, button, state, timestamp):
        self.current_mode.on_controller_button_up(button)

    def controller_motion(self, axis, value, timestamp):
        self.current_mode.on_controller_motion(axis, value)

    def drop(self):
        world.states.drop_state(self.state)
