class BoxSelector:
    def __init__(self):
        self.active = False
        self.rectangle = None

        self.exited = z.Signal()
        self.changed = z.Signal()

    def start_selection(self):
        assert not self.active
        self.p1 = self.p2 = world.window.mouse_pos
        self.active = True
        self.rectangle = z.Rectangle(color=(0, 0, 0, 0.3))
        self.update_rectangle()

    def stop_selection(self):
        assert self.active
        self.active = False
        self.rectangle.drop()
        del self.rectangle
        self.changed.emit((self.p1, self.p2))

    def update_rectangle(self):
        u1 = world.unproject((*self.p1, 0.1))
        u2 = world.unproject((*self.p2, 0.1))
        self.rectangle.layout.position = np.array((u1[0], u1[1], u1[2]))
        self.rectangle.layout.size = np.array((u2[0] - u1[0], u2[1] - u1[1]))
        self.rectangle.layouter()

    def on_mouse_button(self, button, action, mods):
        if button == sdl2.SDL_BUTTON_LEFT and action == 1 and not self.active:
            self.start_selection()
        elif self.active and button == sdl2.SDL_BUTTON_LEFT and action == 0:
            self.stop_selection()

    def on_mouse_motion(self, x, y):
        if self.active:
            self.p2 = (x, y)
            self.update_rectangle()

    def on_keyboard(self, key, scancode, action, mods):
        if action == 1 and key == sdl2.SDLK_ESCAPE:
            if self.active:
                self.stop_selection()
            self.exited.emit()