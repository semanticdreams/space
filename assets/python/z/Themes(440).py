class Themes:
    def __init__(self):
        world.themes = self

        self._themes_classes = [z.DarkTheme, z.LightTheme]
        self._themes = {x.name: x for x in self._themes_classes}

        self.set_theme('dark')

    def set_theme(self, name):
        self.theme = self._themes[name]()

    def cycle_theme(self):
        self.set_theme(
            self._themes_classes[(self._themes_classes.index(self.theme.__class__) + 1) % len(self._themes_classes)].name)

    def drop(self):
        pass
