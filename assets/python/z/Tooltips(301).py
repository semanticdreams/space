class Tooltips:
    def __init__(self):
        self.intersectees = []
        self.texts = {}
        self.active_intersectee = None
        self.labels = {}

    def update(self):
        for label in self.labels.values():
            label.layout.update()

    def create_tooltip(self, intersectee, text):
        self.intersectees.append(intersectee)
        self.texts[intersectee] = text

    def drop_tooltip(self, intersectee):
        del self.texts[intersectee]
        return self.intersectees.remove(intersectee)

    def activate_tooltip(self, intersectee, ray, intersection):
        text = self.texts[intersectee]
        label = z.Button(color=(1, 0, 0, 1), text='hello world', hud=True, focusable=False)
        position = intersection - 0.1 * ray.direction
        label.layout.position = position
        self.labels[intersectee] = label
        self.active_intersectee = intersectee

    def cancel_tooltip(self, intersectee):
        label = self.labels.pop(intersectee)
        label.drop()
        self.active_intersectee = None

    def cancel_all(self):
        pass

    def on_mouse_motion(self, x, y):
        ray = world.screen_pos_ray((x, y), projection=world.hud_projection, camera=world.camera['identity'])
        [f, i, d, o] = z.multi_intersect(ray, self.intersectees, include_obj=True)
        if f:
            if self.active_intersectee is None:
                _hy_anon_var_2 = self.activate_tooltip(o, ray, i)
            else:
                if self.active_intersectee != o:
                    self.cancel_tooltip(self.active_intersectee)
                    _hy_anon_var_1 = self.activate_tooltip(o, ray, i)
                else:
                    _hy_anon_var_1 = None
                _hy_anon_var_2 = _hy_anon_var_1
            _hy_anon_var_3 = _hy_anon_var_2
        else:
            _hy_anon_var_3 = self.cancel_tooltip(self.active_intersectee) if not self.active_intersectee is None else None
        return _hy_anon_var_3