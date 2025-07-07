import time
from util import multi_intersect, ray_from_screen_pos


class Clickables:
    def __init__(self):
        self.projection = world.projection
        self.viewport = world.viewport
        self.camera = world.camera.camera

        self.active = None

        self.last_click = None
        self.last_click_pos = None

        self.right_click_objs = []
        self.right_click_void_callbacks = []

        self.double_click_objs = []

        self.objs = []
        self.left_click_void_callbacks = []

        self.mouse_down_pos = None

        world.states.create_state(name='clickables', on_enter=self.on_enter,
                                  on_leave=self.on_leave)

        world.vim.modes['normal'].add_action_group(z.VimActionGroup('clickables', [
            z.VimAction('enable-clickables', self.enable_clickables, sdl2.SDLK_l),
        ]))

    def enable_clickables(self):
        world.states.transit(state_name='clickables')
        world.vim.set_current_mode('normal')

    def on_enter(self):
        world.window.mouse_button.connect(self.on_mouse_button)
        world.window.keyboard.connect(self.on_keyboard)

    def on_leave(self):
        world.window.mouse_button.disconnect(self.on_mouse_button)
        world.window.keyboard.disconnect(self.on_keyboard)

    def on_keyboard(self, key, scancode, action, mods):
        if action == 1 and key == sdl2.SDLK_ESCAPE:
            world.states.transit_back()

    def register(self, obj):
        self.objs.append(obj)

    def register_right_click(self, obj):
        self.right_click_objs.append(obj)

    def register_right_click_void_callback(self, func):
        self.right_click_void_callbacks.append(func)

    def register_double_click(self, obj):
        self.double_click_objs.append(obj)

    def register_left_click_void_callback(self, func):
        self.left_click_void_callbacks.append(func)

    def unregister_left_click_void_callback(self, func):
        self.left_click_void_callbacks.remove(func)

    def unregister(self, obj):
        self.objs.remove(obj)

    def unregister_right_click(self, obj):
        self.right_click_objs.remove(obj)

    def unregister_right_click_void_callback(self, func):
        self.right_click_void_callbacks.remove(func)

    def unregister_double_click(self, obj):
        self.double_click_objs.remove(obj)

    def on_mouse_button(self, button, action, mods):
        pos = world.window.mouse_pos
        hud_ray = ray_from_screen_pos(pos, world.camera['identity'].get_view_matrix(), world.hud_projection.value,
                                      self.viewport.value)
        ray = ray_from_screen_pos(pos, self.camera.get_view_matrix(), self.projection.value,
                                  self.viewport.value)

        is_near = lambda p1, p2, rsq=100: (p1[0] - p2[0])**2 + (p1[1] - p2[1])**2 < rsq

        if action == 1:
            self.mouse_down_pos = pos
            f, i, d, o = multi_intersect(
                hud_ray,
                [x for x in ((self.double_click_objs + self.objs) if button == sdl2.SDL_BUTTON_LEFT else self.right_click_objs) if x.hud],
                include_obj=True
            )
            if not f:
                f, i, d, o = multi_intersect(
                    ray,
                    [x for x in ((self.double_click_objs + self.objs) if button == sdl2.SDL_BUTTON_LEFT else self.right_click_objs) if not x.hud],
                    include_obj=True
                )
            if f:
                self.active = (i, d, o)
        elif action == 0 and is_near(self.mouse_down_pos, pos):
            if self.active:
                if button == sdl2.SDL_BUTTON_LEFT:
                    self.active[2].on_click(pos, ray, self.active[0])
                    now = time.time()
                    if self.last_click and now - self.last_click < 0.5 and is_near(self.last_click_pos, pos):
                        self.last_click = None
                        self.active[2].on_double_click(pos, ray, self.active[0])
                    else:
                        self.last_click = now
                        self.last_click_pos = pos
                elif action == 0 and button == sdl2.SDL_BUTTON_RIGHT:
                    self.active[2].on_right_click(pos, ray, self.active[0])
            else:
                if button == sdl2.SDL_BUTTON_LEFT:
                    for func in self.left_click_void_callbacks:
                        func(pos, ray)
                elif button == sdl2.SDL_BUTTON_RIGHT:
                    for func in self.right_click_void_callbacks:
                        func(pos, ray)
        if action == 0 and self.active:
            self.active = None

    def drop(self):
        pass
