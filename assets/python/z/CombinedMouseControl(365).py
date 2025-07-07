class CombinedMouseControl:
    def __init__(self):
        pass

    def on_enter(self):
        world.window.mouse_button.connect(self.on_mouse_button)
        world.window.mouse_motion.connect(self.on_mouse_motion)
        world.window.scrolled.connect(self.on_scrolled)
        world.updated.connect(self.on_update)
        world.apps['Hoverables'].on_enter()

    def on_leave(self):
        world.window.mouse_button.disconnect(self.on_mouse_button)
        world.window.mouse_motion.disconnect(self.on_mouse_motion)
        world.window.scrolled.disconnect(self.on_scrolled)
        world.updated.disconnect(self.on_update)
        world.apps['Hoverables'].on_leave()

    def on_mouse_button(self, button, action, mods):
        world.apps['Clickables'].on_mouse_button(button, action, mods)
        world.apps['Spatiolation'].on_mouse_button(button, action, mods)
        if not (world.apps['Clickables'].active or world.apps['Spatiolation'].drag):
            if button == sdl2.SDL_BUTTON_LEFT:
                world.apps['ObjectSelector'].on_mouse_button(button, action, mods)
            else:
                world.camera.fpc.on_mouse_button(button, action, mods)

    def on_mouse_motion(self, x, y):
        if world.apps['Spatiolation'].drag:
            world.apps['Spatiolation'].on_mouse_motion(x, y)
        elif not world.apps['Clickables'].active and world.camera.fpc.drag_active():
            world.camera.fpc.on_mouse_motion(x, y)
        elif world.apps['ObjectSelector'].is_active():
            world.apps['ObjectSelector'].on_mouse_motion(x, y)
        else:
            #world.tooltips.on_mouse_motion(x, y)
            world.apps['Hoverables'].on_mouse_motion(x, y)

    def on_scrolled(self, x, y):
        if world.focus.current and isinstance(world.focus.current.obj, z.Input) and world.focus.current.obj.hovered:
            if y:
                world.focus.current.obj.move_caret('up', y * 3)
            if x:
                world.focus.current.obj.move_caret('right', x * 3)
        else:
            world.camera.fpc.on_scrolled(x, y)

    def on_update(self, delta):
        world.camera.fpc.scroll_update(delta)

    def drop(self):
        self.on_leave()
