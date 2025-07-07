class LineStrip:
    def __init__(self, positions, color):
        self.vector = z.Vector(6 * len(positions))
        self.update(positions, color)

    def update(self, positions, color=None):
        for i, position in enumerate(positions):
            offset = i * 6
            self.vector.array[offset:offset+3] = position
            self.vector.array[offset+3:offset+6] = color

    def drop(self):
        world.lines.drop_line_strip(self)