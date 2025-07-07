default_key_mapping_sdl2 = {
    'move_left': 97,
    'move_right': 101,
    'move_forward': 44,
    'move_backward': 111,
    'look_up': 1073741906,
    'look_down': 1073741905,
    'look_right': 1073741904,
    'look_left': 1073741903,
    'speed': 32
}


class FirstPersonControls:
    def __init__(self, camera=None, window=None,
                 movement_speed=10, look_speed=1,
                 key_mapping=None):
        self.camera = camera
        self.window = window
        self.movement_speed = movement_speed
        self.look_speed = look_speed
        self.mouse_look_speed = 0.001
        self.mouse_move_speed = 0.2

        self.speed_multiplier = 1.0

        self.scroll_speed = np.array((0, 0), float)
        self.max_scroll_speed = 10.0
        self.scroll_acceleration = 2.0
        self.scroll_deceleration = 0.99

        self.drag_look_start = None
        self.drag_move_start = None

        self.keys = world.window.keys#set()

        self.key_mapping = {
            **default_key_mapping_sdl2,
            **(key_mapping or {})
        }

        world.states.create_state(name='fpc', on_enter=self.on_enter, on_leave=self.on_leave)

    def on_enter(self):
        world.window.keyboard.connect(self.on_keyboard)
        world.window.scrolled.connect(self.on_scrolled)
        world.window.mouse_button.connect(self.on_mouse_button)
        world.window.mouse_motion.connect(self.on_mouse_motion)
        if world.gamepads.primary:
            world.gamepads.primary.button_down.connect(self.on_controller_button_down)
        world.updated.connect(self.on_update)

    def on_leave(self):
        world.window.keyboard.disconnect(self.on_keyboard)
        world.window.scrolled.disconnect(self.on_scrolled)
        world.window.mouse_button.disconnect(self.on_mouse_button)
        world.window.mouse_motion.disconnect(self.on_mouse_motion)
        if world.gamepads.primary:
            world.gamepads.primary.button_down.disconnect(
                self.on_controller_button_down)
        world.updated.disconnect(self.on_update)

    def on_controller_button_down(self, button, state, timestamp):
        if button == 20:
            world.states.transit_back()

    def on_keyboard(self, key, scancode, action, mods):
        if action == 1 and key == sdl2.SDLK_ESCAPE:
            world.states.transit_back()
#        else:
#            if action == 1:
#                self.keys.add(key)
#            elif action == 0:
#                self.keys.discard(key)

    def reset_scroll(self):
        self.scroll_speed = np.array((0, 0), float)

    def on_scrolled(self, x, y):
        self.scroll_speed += np.array([x, y]) * self.scroll_acceleration

    def on_mouse_button(self, button, action, mods):
        if button == sdl2.SDL_BUTTON_LEFT:
            if action == 1:
                self.drag_look_start = self.window.mouse_pos
            else:
                self.drag_look_start = None
        elif button == sdl2.SDL_BUTTON_RIGHT:
            if action == 1:
                self.drag_move_start = self.window.mouse_pos
            else:
                self.drag_move_start = None

    def on_mouse_motion(self, x, y):
        if self.drag_look_start is not None:
            dx = x - self.drag_look_start[0]
            dy = y - self.drag_look_start[1]
            self.drag_look_start = x, y
            self.camera.yaw(dx * self.mouse_look_speed)
            self.camera.pitch(dy * self.mouse_look_speed)
        if self.drag_move_start is not None:
            dx = x - self.drag_move_start[0]
            dy = y - self.drag_move_start[1]
            self.drag_move_start = x, y
            self.camera.right(-dx * self.mouse_move_speed)
            self.camera.up(dy * self.mouse_move_speed)

    def drag_active(self):
        return self.drag_look_start is not None or self.drag_move_start is not None

    def drop(self):
        pass

    def scroll_update(self, delta):
        if np.any(self.scroll_speed):
            ray = world.screen_pos_ray(self.window.mouse_pos)
            zoom_factor = self.scroll_speed * np.abs(self.scroll_speed)**1.4 \
                    * self.movement_speed * self.speed_multiplier * 0.09# * delta
            self.camera.right(zoom_factor[0])
            if sdl2.SDLK_LCTRL not in self.keys:
                if zoom_factor[1] > 0:
                    self.camera.set_position(self.camera.position + ray.direction * zoom_factor[1])
                else:
                    self.camera.forward(zoom_factor[1])
            else:
                self.camera.up(zoom_factor[1])

            self.scroll_speed *= np.power(self.scroll_deceleration, delta)
            if np.linalg.norm(self.scroll_speed) < 0.01:
                self.scroll_speed = np.array([0.0, 0.0])
            self.scroll_speed = np.clip(self.scroll_speed, -self.max_scroll_speed, self.max_scroll_speed)


    def on_update(self, delta):
        actions = set(k for k, v in self.key_mapping.items() if v in self.keys)

        if 'speed' in actions:
            self.speed_multiplier = self.speed_multiplier + delta * 20
            self.look_speed_multiplier = 2
        else:
            self.speed_multiplier = max(1, self.speed_multiplier - delta * 100)
            self.look_speed_multiplier = 1

        self.scroll_update(delta)

        if 'move_left' in actions:
            self.camera.right(-delta * self.movement_speed * self.speed_multiplier)
        if 'move_right' in actions:
            self.camera.right(delta * self.movement_speed * self.speed_multiplier)
        if 'move_forward' in actions:
            self.camera.forward(delta * self.movement_speed * self.speed_multiplier)
        if 'move_backward' in actions:
            self.camera.forward(-delta * self.movement_speed * self.speed_multiplier)
        if 'move_up' in actions:
            self.camera.up(delta * self.movement_speed * self.speed_multiplier)
        if 'move_down' in actions:
            self.camera.up(-delta * self.movement_speed * self.speed_multiplier)
        if 'look_up' in actions:
            self.camera.pitch(delta * self.look_speed * self.look_speed_multiplier)
        if 'look_down' in actions:
            self.camera.pitch(-delta * self.look_speed * self.look_speed_multiplier)
        if 'look_right' in actions:
            self.camera.yaw(delta * self.look_speed * self.look_speed_multiplier)
        if 'look_left' in actions:
            self.camera.yaw(-delta * self.look_speed * self.look_speed_multiplier)
        if 'roll_left' in actions:
            self.camera.roll(delta * self.look_speed * self.look_speed_multiplier)
        if 'roll_right' in actions:
            self.camera.roll(-delta * self.look_speed * self.look_speed_multiplier)

        if not world.gamepads.primary:
            return

        axes = world.gamepads.primary.get_axes()

        threshold = 0.1
        axes[(axes > -threshold) & (axes < threshold)] = 0.0

        # triggger buttons
        trigger_move_speed = 0.8
        self.camera.forward(delta * trigger_move_speed * (axes[5] + 1) / 2)
        self.camera.forward(delta * trigger_move_speed * -(axes[4] + 1) / 2)

        look_speed = 0.003
        self.camera.yaw(delta * look_speed * -axes[2])
        self.camera.pitch(delta * look_speed * -axes[3])

        move_speed = 0.4
        self.camera.right(delta * move_speed * axes[0])
        self.camera.forward(delta * move_speed * -axes[1])
