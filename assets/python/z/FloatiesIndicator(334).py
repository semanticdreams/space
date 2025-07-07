class FloatiesIndicator:
    def __init__(self):
        self.floaties = world.apps['Floaties']
        self.floaties.changed.connect(self.floaties_changed)
        self.button = z.ContextButton(
            label='0', color=world.themes.theme.blue[500],
            foreground_color=world.themes.theme.gray[900],
            actions=[
                ('kill', self.kill_triggered),
                ('kill all', self.kill_all_triggered),
            ],
            hud=True,
            focusable=False
        )
        world.apps['Hud'].top_panel.add(self.button)

        self.kill_state = world.states.create_state(name='floaties-kill',
                                                    on_enter=self.on_enter_kill_state,
                                                    on_leave=self.on_leave_kill_state)

    def mouse_button_kill(self, button, action, mods):
        if button == sdl2.SDL_BUTTON_LEFT and action == 0:
            intersector = z.ScreenPosObjectsIntersector(
                world.window.mouse_pos, mapattr(self.floaties.floaties.values(), 'layout'))
            if intersector.nearest_hit:
                floatie = one([x for x in self.floaties.floaties.values()
                           if x.layout == intersector.nearest_hit.obj])
                world.floaties.drop_obj(floatie.obj)
            world.states.transit_back()

    def keyboard_kill(self, key, scancode, action, mods):
        if action == 1 and mods == 0:
            if key == sdl2.SDLK_ESCAPE:
                world.states.transit_back()
            elif key == sdl2.SDLK_x:
                world.states.transit_back()
                current_root_children = [x for x in world.floaties.floaties.keys()
                                         if x.focus.has_current_descendant()]
                if current_root_children:
                    world.floaties.drop_obj(one(current_root_children))

    def on_enter_kill_state(self):
        world.window.mouse_button.connect(self.mouse_button_kill)
        world.window.keyboard.connect(self.keyboard_kill)

    def on_leave_kill_state(self):
        world.window.mouse_button.disconnect(self.mouse_button_kill)
        world.window.keyboard.disconnect(self.keyboard_kill)

    def kill_triggered(self):
        world.states.transit(self.kill_state)

    def kill_all_triggered(self):
        self.floaties.drop_all()

    def floaties_changed(self):
        self.button.set_label(f'{len(self.floaties.floaties.keys())}')

    def drop(self):
        world.states.drop_state(self.kill_state)
        self.button.drop()
