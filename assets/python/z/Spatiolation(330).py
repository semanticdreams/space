class Spatiolation:
    def __init__(self):
        self.active_plane = z.Plane((0, 0, 1), (0, 0, 0))

        self.spatiolatables = []
        self.moved_handlers = {}

        self.drag = None

        world.states.create_state(name='spatiolation', on_enter=self.on_enter,
                                  on_leave=self.on_leave)

    def on_enter(self):
        world.window.mouse_button.connect(self.on_mouse_button)
        world.window.mouse_motion.connect(self.on_mouse_motion)
        world.window.keyboard.connect(self.on_keyboard)

    def on_leave(self):
        world.window.mouse_button.disconnect(self.on_mouse_button)
        world.window.mouse_motion.disconnect(self.on_mouse_motion)
        world.window.keyboard.disconnect(self.on_keyboard)

    def on_keyboard(self, key, scancode, action, mods):
        if action == 1:
            if key == sdl2.SDLK_ESCAPE:
                world.states.transit_back()
            elif key == sdl2.SDLK_0 and self.drag:
                self.drag.plane = self.active_plane
                self.update_spatiolatable_position()
            elif key == sdl2.SDLK_LEFT:
                o = world.focus.current.obj.spatiolator
                o.set_position(o.position + np.array((-10, 0, 0)))
            elif key == sdl2.SDLK_RIGHT:
                o = world.focus.current.obj.spatiolator
                o.set_position(o.position + np.array((10, 0, 0)))
            elif key == sdl2.SDLK_UP:
                o = world.focus.current.obj.spatiolator
                o.set_position(o.position + np.array((0, 10, 0)))
            elif key == sdl2.SDLK_DOWN:
                o = world.focus.current.obj.spatiolator
                o.set_position(o.position + np.array((0, -10, 0)))

    def on_mouse_button(self, button, action, mods):
        if button == sdl2.SDL_BUTTON_LEFT:
            if action == 1:
                intersector = z.ScreenPosObjectsIntersector(
                    world.window.mouse_pos, self.spatiolatables)
                if intersector.nearest_hit:
                    start_pos = intersector.nearest_hit.intersection
                    forward_vector = world.camera.camera.get_forward()
                    axis_vectors = [np.array(v) for v in [(1, 0, 0), (0, 1, 0), (0, 0, 1), (-1, 0, 0), (0, -1, 0), (0, 0, -1)]]
                    closest_vector = max(axis_vectors, key=lambda v: np.dot(v, forward_vector))
                    plane = z.Plane(closest_vector, start_pos)
                    self.drag = z.DragMoveOperation(
                        intersector.nearest_hit.obj, start_pos,
                        intersector.nearest_hit.obj.get_position() - intersector.nearest_hit.intersection,
                        plane
                    )
            else:
                if self.drag:
                    if self.drag.spatiolator in self.moved_handlers:
                        self.moved_handlers[self.drag.spatiolator](self.drag)
                self.drag = None

    def on_mouse_motion(self, x, y):
        if self.drag:
            self.update_spatiolatable_position()

    def update_spatiolatable_position(self):
        ray = world.screen_pos_ray(world.window.mouse_pos)
        intersector = z.RayPlaneIntersector(ray, self.drag.plane)
        position = intersector.intersection + self.drag.offset
        self.drag.spatiolator.set_position(position)

    def add_spatiolatable(self, obj, on_moved=None):
        self.spatiolatables.append(obj)
        if on_moved:
            self.moved_handlers[obj] = on_moved

    def remove_spatiolatable(self, obj):
        self.spatiolatables.remove(obj)

    def drop(self):
        pass
