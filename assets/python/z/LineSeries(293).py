class LineSeries:
    def __init__(self, x_values, y_values, position=None, color=[1, 0, 0]):
        self.x_values = np.asarray(x_values)
        self.y_values = np.asarray(y_values)
        self.x_axis = None
        self.y_axis = None
        self.line_strip = None
        self.position = [0, 0, 0] if position is None else np.asarray(position, float)
        self.scale = np.array([1, 1, 1])
        self.color = np.asarray(color, float)

    def update_line_strip(self):
        world.lines.drop_line_strip(self.line_strip) if self.line_strip else None
        normalized_x_values = self.normalize_values(self.x_values, self.x_axis)
        normalized_y_values = self.normalize_values(self.y_values, self.y_axis)
        points = np.asarray(self.scale) * np.stack([normalized_x_values, normalized_y_values, np.zeros(len(normalized_x_values))], axis=-1)
        self.line_strip = world.lines.create_line_strip(points + self.position, self.color)

    def set_position(self, position):
        self.position = np.asarray(position, float)
        return self.update_line_strip()

    def set_scale(self, scale):
        self.scale = np.asarray(scale, float)
        return self.update_line_strip()

    def attach_x_axis(self, axis):
        self.x_axis = axis

    def attach_y_axis(self, axis):
        self.y_axis = axis

    def normalize_values(self, values, axis):
        return z.Normalizer(values, fixed_min_val=axis.range[0], fixed_max_val=axis.range[1]).result

    def drop(self):
        return world.lines.drop_line_strip(self.line_strip)