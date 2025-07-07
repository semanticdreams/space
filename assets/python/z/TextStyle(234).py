class TextStyle:
    def __init__(self, font=None, color=(1, 0, 0, 1), scale=2):
        self.color = np.asarray(color, float)
        self.font = font or world.themes.theme.font
        self.scale = scale
