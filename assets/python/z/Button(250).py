from util import adjust_perceptual_color_brightness, wrap_text
class Button:
    def __init__(self, text='', hud=False, focusable=True, focus_parent=world.focus,
                 background_color=None,
                 centered=True, foreground_color=None, icon=None,
                 padding_insets=(1, 0.8), font_scale=2,
                 wrap=30, on_click=None, on_right_click=None, on_double_click=None):
        self.hud = hud
        self.wrap = wrap
        self.font_scale = font_scale
        self.icon = icon or (text[5:] if text.startswith('icon:') else None)
        self.background_color = world.themes.theme.button_background_color if background_color is None else background_color
        self.foreground_color = foreground_color or world.themes.theme.button_foreground_color
        if on_click is not None:
            self.on_click = on_click
        if on_right_click is not None:
            self.on_right_click = on_right_click
        if on_double_click is not None:
            self.on_double_click = on_double_click

        if self.icon:
            self.text = z.TextSpan(
                codepoints=[world.apps['Icons'][self.icon]], hud=hud,
                style=z.TextStyle(color=self.foreground_color, font=world.apps['Icons'].font, scale=self.font_scale))
        else:
            self.text = z.Text(
                wrap_text(text, wrap) if wrap else text,
                hud=hud,
                style=z.TextStyle(color=self.foreground_color, scale=self.font_scale)
            )
        self.padding = z.Padding(self.text.layout, padding_insets)
        self.centered = z.Aligned(self.padding.layout, axis='x', alignment='center' if centered else 'start')
        self.rectangle = z.Rectangle(hud=hud, color=self.background_color)
        self.stack = z.Stack([self.rectangle.layout, self.centered.layout])
        self.layout = self.stack.layout

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
        if self.focusable:
            world.focus.set_focus(self.focus)
        self.clicked.emit(f, i, d)

    def set_hud(self, hud):
        self.text.set_hud(hud)
        self.rectangle.set_hud(hud)

    def on_right_click(self, f, i, d):
        if self.focusable:
            world.focus.set_focus(self.focus)
        self.right_clicked.emit(f, i, d)

    def on_double_click(self, f, i, d):
        self.double_clicked.emit(f, i, d)

    def set_color(self, color):
        self.background_color = np.asarray(color, float)
        self.update_colors()

    def set_text(self, text):
        self.text.set_text(wrap_text(text, self.wrap) if self.wrap else text)

    def intersect(self, ray):
        return self.rectangle.intersect(ray)

    def update_colors(self):
        self.rectangle.set_color(world.themes.theme.focused_background_color \
                                 if self.focused else adjust_perceptual_color_brightness(
                                     self.background_color, -0.2 if self.hovered else 0.0))

    def focus_changed(self, focused):
        self.focused = focused
        self.update_colors()
        if focused:
            world.vim.modes['normal'].add_action_group(z.VimActionGroup('button', [
                        z.VimAction('submit', lambda: self.on_click(None, None, None), sdl2.SDLK_RETURN),
            ]))
        else:
            world.vim.modes['normal'].remove_action_group('button')

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
        if self.focus:
            self.focus.disconnect()
        self.stack.drop()
        self.rectangle.drop()
        self.centered.drop()
        self.padding.drop()
        self.text.drop()
        if self.focus:
            self.focus.drop()
