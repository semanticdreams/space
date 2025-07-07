class Gamepads:
    def __init__(self):
        self.gamepads = []
        self.primary = None
        self.gamepad_added = z.Signal()
        self.gamepad_removed = z.Signal()
        self.reload()

    def add(self, joystick_device_index):
        gamepad = z.Gamepad(joystick_device_index)
        self.gamepads.append(gamepad)
        if self.primary is None:
            self.primary = gamepad
        self.gamepad_added.emit(gamepad)
        return gamepad

    def remove(self, sdl_id):
        gamepad = one(list(filter(lambda x: x.sdl_id == sdl_id, self.gamepads)))
        gamepad.drop()
        self.gamepads.remove(gamepad)
        if self.primary == gamepad:
            self.primary = self.gamepads[0] if self.gamepads else None
        self.gamepad_removed.emit(gamepad)

    def reload(self):
        self.gamepads = [z.Gamepad(i) for i in range(sdl2.SDL_NumJoysticks())
                         if sdl2.SDL_IsGameController(i)]
        self.primary = self.gamepads[0] if self.gamepads else None

    def __getitem__(self, key):
        return self.gamepads[key]

    def dump(self):
        return [x.dump() for x in self.gamepads]

    def drop(self):
        self.primary = None
        for gamepad in self.gamepads:
            gamepad.drop()
        self.gamepads = []
