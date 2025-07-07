class ViewportAlignment:
    def __init__(self, distance=120, padding=0, projection=None):
        self.distance = distance
        self.padding = padding
        self.world = world
        self.projection = projection or world.projection
        self.width, self.height = self.viewport_dimensions()

    def viewport_dimensions(self):
        h = 2 * self.distance * math.tan(math.radians(self.projection.fov) / 2)
        w = h * self.projection.aspect
        return w, h

    def align_to_viewport(self, target=[0, 0, 0]):
        return [
            (target[0] + self.width / 2) - self.padding,
            (target[1] - self.height / 2) + self.padding,
            target[2] + self.distance
        ]

    def max_target_size(self):
        max_width = self.width - 2 * self.padding
        max_height = self.height - 2 * self.padding
        return max_width, max_height

    def distance_for_target_size(self, target_width, target_height, padding=0):
        padded_width = target_width + 2 * padding
        padded_height = target_height + 2 * padding

        target_aspect = padded_width / padded_height
        distance_width = (padded_width / 2) / math.tan(math.radians(self.projection.aspect * self.projection.fov) / 2)
        distance_height = (padded_height / 2) / math.tan(math.radians(self.projection.fov) / 2)

        # Choose the maximum distance to ensure both dimensions fit within the viewport
        distance = max(distance_width, distance_height)
        return distance