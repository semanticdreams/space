class Hoverables:
    def __init__(self):
        self.objs = []
        self.active = None

    def add_hoverable(self, obj):
        self.objs.append(obj)

    def remove_hoverable(self, obj):
        self.objs.remove(obj)
        if self.active == obj:
            self.active.on_hovered(False)
            self.active = None

    def on_leave(self):
        if self.active:
            self.active.on_hovered(False)
            self.active = False

    def on_enter(self):
        self.apply_mouse_pos(world.window.mouse_pos)

    def on_mouse_motion(self, x, y):
        self.apply_mouse_pos((x, y))

    def apply_mouse_pos(self, pos):
        ray = world.screen_pos_ray(pos)
        hud_ray = world.screen_pos_ray(pos, projection=world.hud_projection, camera=world.camera['identity'])

        f, i, d, o = util.multi_intersect(hud_ray, [x for x in self.objs if x.hud], include_obj=True)
        if not f:
            f, i, d, o = util.multi_intersect(ray, [x for x in self.objs if not x.hud], include_obj=True)

        if f:
            if self.active:
                if self.active != o:
                    self.active.on_hovered(False)
                    o.on_hovered(True)
                    self.active = o
            else:
                o.on_hovered(True)
                self.active = o
        elif self.active:
            self.active.on_hovered(False)
            self.active = False

    def drop(self):
        pass
