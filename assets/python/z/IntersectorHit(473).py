class IntersectorHit:
    def __init__(self, hit, intersection, distance, obj):
        self.hit = hit
        self.intersection = intersection
        self.distance = distance
        self.obj = obj

    def __repr__(self):
        return f'Hit(hit={self.hit}, intersection={self.intersection}, distance={self.distance}, obj={self.obj})'