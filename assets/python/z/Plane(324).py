class Plane:
    def __init__(self, normal, point):
        self.normal = np.asarray(normal, float)
        self.point = np.asarray(point, float)