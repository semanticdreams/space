class CenteredAheadLayout:
    def __init__(self, child, camera=None, distance=100, name=''):
        self.layout = z.Layout(children=[child.layout], layouter=self.layouter, name=f'centered-ahead({name})')

        self.camera = camera or world.camera.camera
        self.distance = distance

    def layouter(self, constraints):
        self.layout.children[0].depth_offset_index = self.layout.depth_offset_index
        box = self.layout.children[0].layouter(constraints)
        self.layout.child_positions[0] = self.camera.get_ahead_position(self.distance) - box / 2
        return box

    def drop(self):
        self.layout.drop()
