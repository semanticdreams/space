class ObjectSelector:
    def __init__(self):
        self.selectables = []
        self.selected = []

        self.exited = z.Signal()
        self.changed = z.Signal()

        self.box_selector = z.BoxSelector()
        self.box_selector.changed.connect(self.on_box_changed)
        self.box_selector.exited.connect(self.exited.emit)

    def is_active(self):
        return self.box_selector.active

    def set_selectables(self, objs):
        prev_selected = set(self.selected)
        self.selected = prev_selected & set(objs)
        self.selectables = objs
        if prev_selected != self.selected:
            self.changed.emit()
        self.selected = list(self.selected)

    def add_selectables(self, objs):
        self.selectables.extend(objs)

    def remove_selectables(self, objs):
        for obj in objs:
            self.selectables.remove(obj)
        prev_selected = set(self.selected)
        self.selected = prev_selected & set(self.selectables)
        if prev_selected != self.selected:
            self.changed.emit()
        self.selected = list(self.selected)

    def unselect_all(self):
        self.selected = []
        self.changed.emit()

    def on_box_changed(self, box):
        unproject = world.unproject
        p1, p2 = box

        b_top = unproject((p1[0], p1[1], 1.0)) \
                - unproject((p1[0], p1[1], 0.0))
        c_top = unproject((p2[0], p1[1], 1.0)) \
                - unproject((p1[0], p1[1], 0.0))
        b_bottom = unproject((p1[0], p2[1], 1.0)) \
                - unproject((p1[0], p2[1], 0.0))
        c_bottom = unproject((p2[0], p2[1], 1.0)) \
                - unproject((p1[0], p2[1], 0.0))
        b_left = b_bottom
        c_left = unproject((p1[0], p1[1], 1.0)) \
                - unproject((p1[0], p2[1], 0.0))
        b_right = unproject((p2[0], p1[1], 1.0)) \
                - unproject((p2[0], p1[1], 0.0))
        c_right = unproject((p2[0], p2[1], 1.0)) \
                - unproject((p2[0], p1[1], 0.0))

        self.selected = []

        for selectable in self.selectables:
            x_top = selectable.layout.position - unproject((p1[0], p1[1], 0.0))
            x_bottom = selectable.layout.position - unproject((p1[0], p2[1], 0.0))
            x_left = selectable.layout.position - unproject((p1[0], p2[1], 0.0))
            x_right = selectable.layout.position - unproject((p2[0], p1[1], 0.0))

            det_top = np.linalg.det(np.array([b_top, c_top, x_top]))
            det_bottom = np.linalg.det(np.array([b_bottom, c_bottom, x_bottom]))

            if np.sign(det_top) == np.sign(det_bottom):
                continue

            det_left = np.linalg.det(np.array([b_left, c_left, x_left]))
            det_right = np.linalg.det(np.array([b_right, c_right, x_right]))

            if np.sign(det_left) != np.sign(det_right):
                continue

            self.selected.append(selectable)

        self.changed.emit()

    def on_mouse_button(self, button, action, mods):
        self.box_selector.on_mouse_button(button, action, mods)

    def on_mouse_motion(self, x, y):
        self.box_selector.on_mouse_motion(x, y)

    def on_keyboard(self, key, scancode, action, mods):
        self.box_selector.on_keyboard(key, scancode, action, mods)

    def drop(self):
        pass
