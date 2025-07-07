class Floatie:
    def __init__(self, obj, tile, code_entity=None, hud=False):
        self.hud = hud
        if hud:
            obj.set_hud(hud)
        self.obj = obj
        self.tile = tile
        self.code_entity = code_entity
        if hasattr(obj, 'name'):
            if isinstance(obj.name, str):
                self.title = obj.name
            else:
                self.title = obj.name.get()
                obj.name.changed.connect(self.name_changed)
        elif hasattr(obj, 'get_name'):
            self.title = obj.get_name()
        else:
            self.title = str(obj)

        self.focus = self.obj.focus
        self.dialog = z.Dialog(self.title, self.obj)
        self.dialog.closed.connect(lambda: world.floaties.drop_obj(self.obj))
        self.layout = self.dialog.layout
        self.handle = self

    def get_position(self):
        return self.layout.position

    def set_position(self, position):
        self.layout.position = position
        self.layout.mark_layout_dirty()

    def set_rotation(self, rotation):
        self.layout.rotation = rotation
        self.layout.mark_layout_dirty()

    def intersect(self, ray):
        return self.dialog.title_bar.label.layout.intersect(ray)

    def name_changed(self):
        self.dialog.title_bar.label.set_text(self.obj.name.get())

    def drop(self):
        if hasattr(self.obj, 'name') and not isinstance(self.obj.name, str):
            self.obj.name.changed.disconnect(self.name_changed)
        self.dialog.drop()
