class TitleBar:
    def __init__(self, title, actions, color=None):
        self.color = world.themes.theme.title_bar_background_color if color is None else color
        self.label = z.Label(title, color=world.themes.theme.title_bar_foreground_color)
        self.actions = actions
        self.buttons = []
        for name, func in actions:
            button = z.Button(name, on_click=lambda f, i, d, func=func: func(), focusable=False,
                            background_color=self.color,
                            foreground_color=world.themes.theme.title_bar_button_foreground_color,
                             )
            self.buttons.append(button)
        self.row = z.Flex([z.FlexChild(self.label.layout, flex=1),
                         *[z.FlexChild(x.layout) for x in self.buttons]], yalign='largest', xalign='start',
                        xspacing=0)
        self.rectangle = z.Rectangle(color=self.color)
        self.stack = z.Stack([self.rectangle.layout, self.row.layout])
        self.layout = self.stack.layout

    def drop(self):
        self.stack.drop()
        self.row.drop()
        for button in self.buttons:
            button.drop()
        self.label.drop()
        self.rectangle.drop()
