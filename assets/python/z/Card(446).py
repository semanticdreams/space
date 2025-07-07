class Card:
    def __init__(self, child):
        self.padding = z.Padding(child)
        self.rectangle = z.Rectangle(color=world.themes.theme.card_background_color)
        self.stack = z.Stack([self.rectangle.layout, self.padding.layout],
                                     name='card')
        self.layout = self.stack.layout

    def drop(self):
        self.stack.drop()
        self.rectangle.drop()
        self.padding.drop()
