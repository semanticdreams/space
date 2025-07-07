class Label:
    def __init__(self, text='', hud=False, color=None, text_style=None, min_width=None,
                 padding_insets=(1, 1)):
        self.color = world.themes.theme.label_color if color is None else color
        self.text = z.Text(text, hud=hud, min_width=min_width,
                         style=z.TextStyle(color=self.color) if text_style is None else text_style)
        self.padding = z.Padding(self.text.layout, padding_insets)
        self.layout = self.padding.layout

    def intersect(self, ray):
        return self.layout.intersect(ray)

    def set_text(self, text):
        self.text.set_text(text)

    def drop(self):
        self.padding.drop()
        self.text.drop()
