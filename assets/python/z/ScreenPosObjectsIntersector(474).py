import operator


class ScreenPosObjectsIntersector:
    def __init__(self, pos, objs):
        self.world = world
        self.camera = self.world.camera.camera
        self.viewport = self.world.viewport
        self.projection = self.world.projection

        self.pos = pos
        self.objs = objs

        self.ray = world.screen_pos_ray(self.pos)

        self.hits = []

        for obj in self.objs:
            hit, intersection, distance = obj.intersect(self.ray)
            if hit:
                self.hits.append(z.IntersectorHit(hit, intersection, distance, obj))

        self.hits.sort(key=operator.attrgetter('distance'))
        self.nearest_hit = self.hits[0] if self.hits else None