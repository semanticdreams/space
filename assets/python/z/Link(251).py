class Link:
    def __init__(self, text='', hud=False, focusable=True, focus_parent=world.focus,
                 foreground_color=None, style=None,
                 on_click=None, on_right_click=None, on_double_click=None):
        self.hud = hud
        self.foreground_color = foreground_color or world.themes.theme.button_foreground_color
        self.style = z.TextStyle(color=self.foreground_color) if style is None else style

        if on_click is not None:
            self.on_click = on_click
        if on_right_click is not None:
            self.on_right_click = on_right_click
        if on_double_click is not None:
            self.on_double_click = on_double_click

        self.text = z.Text(text, hud=hud, style=self.style)
        self.layout = self.text.layout

        self.focus = None
        self.focused = False
        self.focusable = focusable

        self.hovered = False

        if self.focusable:
            self.focus = focus_parent.add_child(self, on_changed=self.focus_changed)

        world.apps['Hoverables'].add_hoverable(self)

        self.clicked = z.Signal()
        self.right_clicked = z.Signal()
        self.double_clicked = z.Signal()

        world.apps['Clickables'].register(self)
        world.apps['Clickables'].register_right_click(self)
        world.apps['Clickables'].register_double_click(self)

    def on_click(self, f, i, d):
        self.clicked.emit(f, i, d)

    def on_right_click(self, f, i, d):
        self.right_clicked.emit(f, i, d)

    def on_double_click(self, f, i, d):
        self.double_clicked.emit(f, i, d)

    def set_text(self, text):
        self.text.set_text(wrap_text(text, self.wrap) if self.wrap else text)

    def intersect(self, ray):
        return self.layout.intersect(ray)

    def update_colors(self):
        pass
        #self.rectangle.set_color(world.themes.theme.focused_background_color \
        #                         if self.focused else adjust_perceptual_color_brightness(
        #                             self.background_color, -0.2 if self.hovered else 0.0))

    def focus_changed(self, focused):
        self.focused = focused
        self.update_colors()

    def on_hovered(self, entered):
        if entered:
            world.apps['SystemCursors'].set_cursor('hand')
        else:
            world.apps['SystemCursors'].set_cursor('arrow')
        self.hovered = entered
        self.update_colors()

    def drop(self):
        world.apps['Hoverables'].remove_hoverable(self)
        world.apps['Clickables'].unregister(self)
        world.apps['Clickables'].unregister_right_click(self)
        world.apps['Clickables'].unregister_double_click(self)
        self.text.drop()
        if self.focus:
            self.focus.drop()
