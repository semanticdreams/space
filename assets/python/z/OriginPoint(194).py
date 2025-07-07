class OriginPoint:
    def __init__(self):
        self.point = world.renderers.points.create_point(size=10)

    def drop(self):
        world.renderers.points.drop_point(self.point)
