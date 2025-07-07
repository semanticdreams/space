class Lines:
    def __init__(self):
        pass

    def create_line(self, start, end, color):
        h = world.renderers.line_vector.allocate(12)
        self.update_line(h, start, end, color)
        return h

    def create_line_strip(self, positions, color=(0.5, 0.5, 0.5)):
        line_strip = z.LineStrip(positions, color)
        world.renderers.line_strips.append(line_strip)
        return line_strip

    def drop_line(self, handle):
        world.renderers.line_vector.delete(handle)

    def drop_line_strip(self, handle):
        world.renderers.line_strips.remove(handle)

    def update_line(self, handle, start=None,
                    end=None, color=None):
        v = world.renderers.line_vector.view(handle)
        if start is not None:
            v[0:3] = start
        if color is not None:
            v[3:6] = color
            v[9:12] = color
        if end is not None:
            v[6:9] = end

    def drop(self):
        world.renderers.line_strips.clear()
