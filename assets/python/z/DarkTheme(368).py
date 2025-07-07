from pygments.token import Token

from util import create_color_swatch


class DarkTheme:
    name = 'dark'

    red = create_color_swatch((1, 0, 0, 1))
    green = create_color_swatch((0, 1, 0, 1))
    blue = create_color_swatch((0, 0, 1, 1))
    yellow = create_color_swatch((1, 1, 0, 1))
    gray = grey = create_color_swatch((0.5, 0.5, 0.5, 1))
    white = (1, 1, 1, 1)
    black = (0, 0, 0, 1)
    coral = (1.0, 0.5, 0.31, 1.0)
    turquoise = (0.25, 0.88, 0.82, 1.0)
    lavender = (0.9, 0.9, 0.98, 1.0)
    salmon = (0.98, 0.5, 0.45, 1.0)
    indigo = (0.29, 0.0, 0.51, 1.0)
    mint = (0.6, 1.0, 0.6, 1.0)
    peach = (1.0, 0.85, 0.73, 1.0)
    periwinkle = (0.8, 0.8, 1.0, 1.0)
    magenta = (1.0, 0.0, 1.0, 1.0)
    teal = (0.0, 0.5, 0.5, 1.0)
    plum = (0.56, 0.27, 0.52, 1.0)
    amber = (1.0, 0.75, 0.0, 1.0)

    primary = create_color_swatch((0.4, 0.4, 1, 1))
    secondary = create_color_swatch((0.4, 1.0, 0.4, 1))
    tertiary = create_color_swatch((1, 0.4, 0.4, 1))

    dialog_background_color = gray[700]

    border_width = 0

    label_color = gray[100]

    card_background_color = gray[800]

    button_background_color = gray[800]
    button_foreground_color = gray[100]
    button_border_color = black
    button_border_width = border_width

    input_background_color = gray[800]
    input_background_color_unsubmitted_change = gray[600]
    input_foreground_color = gray[100]
    input_caret_color = gray[100]
    input_border_color = gray[500]
    input_border_width = border_width

    syntax_colors = {
        Token:               (1.0, 0.0, 1.0, 1.0),
        Token.Keyword:       (1.0, 0.2, 0.4, 1.0),  # pinkish red
        Token.Name:          (0.6, 0.8, 1.0, 1.0),  # light blue
        Token.Name.Function: (0.4, 1.0, 0.8, 1.0),  # aqua
        Token.Name.Class:    (1.0, 0.6, 0.2, 1.0),  # orange
        Token.Name.Builtin:  (0.8, 0.4, 1.0, 1.0),  # violet
        Token.Literal.String:(0.6, 1.0, 0.6, 1.0),  # light green
        Token.Literal.Number:(1.0, 1.0, 0.5, 1.0),  # yellow
        Token.Operator:      (1.0, 0.8, 0.4, 1.0),  # gold
        Token.Comment:       (0.5, 0.5, 0.5, 1.0),  # gray
        Token.Punctuation:   (0.9, 0.9, 0.9, 1.0),  # near-white
        Token.Text:          (0.9, 0.9, 0.9, 1.0),  # default text
        Token.Error:         (1.0, 0.0, 0.0, 1.0),  # bright red
    }

    background_color = (0.1, 0.1, 0.1, 1)

    text_color = (1, 1, 1, 1)

    title_bar_background_color = gray[900]
    title_bar_foreground_color = gray[100]
    title_buttons_color = title_bar_button_background_color = title_bar_button_border_color = gray[900]
    title_bar_button_foreground_color = gray[100]
    title_bar_button_border_width = 0

    focused_border_color = blue[500]
    focused_background_color = (0, 0, 0.1, 1)

    def __init__(self):
        self.fontsdir = os.path.join(world.assets_path, 'ubuntu-font/msdf')
        self.font = self.get_font_by_name('UbuntuMono-R')
        self.italic_font = self.get_font_by_name('UbuntuMono-RI')

    def get_font_by_name(self, name):
        return z.Font(os.path.join(self.fontsdir, f'{name}.png'),
                         os.path.join(self.fontsdir, f'{name}.json'))

    def get_syntax_color_for_token_type(self, token_type):
        while token_type is not Token:
            if token_type in self.syntax_colors:
                break
            token_type = token_type.parent
        return self.syntax_colors[token_type]


    def drop(self):
        self.font.drop()
