class RayPlaneIntersector:
    def __init__(self, ray, plane):
        self.ray = ray
        self.plane = plane

        self.hit = False

        denom = np.dot(self.plane.normal, self.ray.direction)
        if abs(denom) > 0.0001:
            t = np.dot(self.plane.normal, self.plane.point - self.ray.origin) / denom
            if t >= 0:
                self.intersection = self.ray.origin + self.ray.direction * t
                self.distance = t
                self.hit = True