class Spatiolator:
    __slots__ = ('obj', 'handle','changed')

    def __init__(self, obj=None, handle=None, changed=None):
        self.obj = obj
        self.handle = handle or obj
        self.changed = changed

    @property
    def position(self):
        return self.obj.position
        #return self.obj.get_position()
        
    def get_position(self):
        return self.position

    def set_position(self, position):
        self.obj.position = position
        self.obj.mark_layout_dirty()
        #self.obj.set_position(position)
        if self.changed:
            self.changed()

    def set_rotation(self, rotation):
        #self.obj.set_rotation(rotation)
        self.obj.rotation = rotation
        self.obj.mark_layout_dirty()

    def intersect(self, ray):
        return self.handle.intersect(ray)