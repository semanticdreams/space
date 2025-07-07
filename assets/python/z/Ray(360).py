class Ray:
    def __init__(self, origin, direction):
        self.origin = np.asarray(origin, float)
        self.direction = np.asarray(direction, float)