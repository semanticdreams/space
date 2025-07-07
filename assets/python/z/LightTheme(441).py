class LightTheme(z.DarkTheme):
    name = 'light'

    red = create_color_swatch((1, 0, 0, 1))
    green = create_color_swatch((0, 0.6, 0, 1))
    blue = create_color_swatch((0, 0.3, 1, 1))
    yellow = create_color_swatch((1, 1, 0, 1))
    gray = grey = create_color_swatch((0.9, 0.9, 0.9, 1))
    white = (1, 1, 1, 1)
    black = (0, 0, 0, 1)

    primary = create_color_swatch((0.2, 0.2, 0.8, 1))
    secondary = create_color_swatch((0.2, 0.7, 0.2, 1))
    tertiary = create_color_swatch((0.9, 0.3, 0.3, 1))

    dialog_background_color = gray[100]

    border_width = 0

    label_color = gray[900]

    button_background_color = gray[300]
    button_foreground_color = black
    button_border_color = gray[600]
    button_border_width = border_width

    input_background_color = gray[100]
    input_background_color_unsubmitted_change = gray[200]
    input_foreground_color = black
    input_caret_color = gray[100]
    input_border_color = gray[500]
    input_border_width = border_width

    background_color = (0.98, 0.98, 0.98, 1)

    text_color = (0, 0, 0, 1)

    title_bar_background_color = gray[200]
    title_bar_foreground_color = black
    title_buttons_color = title_bar_button_background_color = title_bar_button_border_color = gray[300]
    title_bar_button_foreground_color = black
    title_bar_button_border_width = 0

    focused_border_color = blue[500]
    focused_background_color = (0.9, 0.9, 1.0, 1)

    def __init__(self):
        fontsdir = os.path.join(world.datadir, 'msdf')
        self.font = z.Font(os.path.join(fontsdir, 'UbuntuMono-R.png'),
                         os.path.join(fontsdir, 'UbuntuMono-R.json'))

    def drop(self):
        self.font.drop()
