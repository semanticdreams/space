class Circles:
    def __init__(self):
        pass

    def generate_circle_positions(self, radius, num_segments=100):
        angles = np.linspace(0, 2 * np.pi, num_segments, endpoint=True)
        x = radius * np.cos(angles)
        y = radius * np.sin(angles)
        z = np.zeros_like(x)
        positions = np.column_stack((x, y, z))
        return positions

    def create_circle(self, position, radius, color):
        return world.lines.create_line_strip(position + self.generate_circle_positions(radius), color)

    def drop_circle(self, handle):
        handle.drop()

    def drop(self):
        pass
