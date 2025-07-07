class InputText:
    def __init__(self, input, style=None, hud=False, syntax_coloring=False):
        self.dropped = False
        self.input = input
        self.style = style
        self.hud = hud
        self.syntax_coloring = syntax_coloring

        self.caret_rectangle = z.RRectangle(
            hidden=True,
            color=world.themes.theme.input_caret_color)

        if self.hud:
            self.vector = world.renderers.get_hud_text_vector(self.style.font)
        else:
            self.vector = world.renderers.get_scene_text_vector(self.style.font)

        self.handle = None

        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter,
                               name='input-text')

    def set_hud(self, hud):
        if hud != self.hud:
            if self.handle:
                self.vector.delete(self.handle)
                self.handle = None
            if hud:
                self.vector = world.renderers.get_hud_text_vector(self.style.font)
            else:
                self.vector = world.renderers.get_scene_text_vector(self.style.font)
            self.hud = hud
            self.update_visible_text()

    def measurer(self):
        assert not self.dropped
        font = self.style.font
        self.layout.measure = np.array((0, 0, 0), float)
        self.line_gap = 0.5
        self.line_height = (font.meta['metrics']['ascender'] - font.meta['metrics']['descender']) * self.style.scale
        self.layout.measure[1] = self.line_height * len(self.visible_lines) \
                + self.line_gap * (len(self.visible_lines) - 1)
        self.layout.measure[0] = font.advance * self.style.scale * self.input.chars_per_line
        #max_x_size = 0.0
        #for line in self.visible_lines:
        #    x_size = 0.0
        #    for char in line:
        #        codepoint = ord(char)
        #        g = font.glyph_map.get(codepoint, font.glyph_map.get(65533))
        #        advance = g['advance'] * self.style.scale
        #        x_size += advance
        #    max_x_size = max(max_x_size, x_size)
        #self.layout.measure[0] = max_x_size

    def update_caret_rectangle(self):
        self.caret_rectangle.set_size((
            0.2 if self.input.inserting else \
            self.style.font.advance * self.style.scale,
            (self.style.font.meta['metrics']['ascender'] \
             - self.style.font.meta['metrics']['descender']) * self.style.scale,
        ))
        self.caret_rectangle.set_rotation(self.layout.rotation)
        self.caret_rectangle.set_depth_offset_index(self.layout.depth_offset_index + 1)

        p = self.layout.position.copy()
        location = self.input.caret_location.copy()
        location[0] -= self.input.scroll_offset[0]
        location[1] -= self.input.scroll_offset[1]

        p[0] += 1.0 * location[0]
        p[1] += self.layout.size[1] - self.line_height

        assert self.style.font.monospace == True
        p[1] -= (self.line_height + self.line_gap) * location[1]

        if self.input.inserting:
            p[0] -= self.caret_rectangle.size[0] / 2
        #p[1] += self.style.font.meta['metrics']['descender'] * self.style.scale
        #p[2] += 0.02
        self.caret_rectangle.set_position(p)

        self.caret_rectangle.update()

    def update_color_map(self):
        from pygments import lex
        from pygments.lexers import PythonLexer
        from collections import defaultdict
        lexer = PythonLexer()
        self.token_map = defaultdict(dict)
        line, column = 0, 0
        for token_type, token_value in lex(self.input.text, lexer):
            for char in token_value:
                if char == '\n':
                    line += 1
                    column = 0
                else:
                    self.token_map[line][column] = \
                            world.themes.theme.get_syntax_color_for_token_type(token_type)
                    column += 1

    def layouter(self):
        assert not self.dropped
        self.input.update_rectangle() # TODO move
        font = self.style.font
        # TODO why is layouter even called with size=0,0,0 at first?
        should_update_visible_text = False
        new_chars_per_line = int(self.layout.size[0] // (font.advance * self.style.scale))
        if new_chars_per_line and self.input.chars_per_line != new_chars_per_line:
            self.input.set_chars_per_line(new_chars_per_line)
            should_update_visible_text = True
        new_max_lines = int((self.layout.size[1] + self.line_gap) // (self.line_height + self.line_gap))
        if new_max_lines and new_max_lines != self.input.max_lines:
            assert new_max_lines > 0
            self.input.max_lines = new_max_lines
            should_update_visible_text = True
        if should_update_visible_text:
            self.update_visible_text(update_layout=False)
        char_vertices_len = 10 * 6
        x_cursor, y_cursor = 0.0, self.layout.size[1] - font.meta['metrics']['ascender'] * self.style.scale
        v = self.vector.view(self.handle)
        i = 0
        for line_idx, line in enumerate(self.visible_lines):
            if line:
                for char_idx, (char, color) in enumerate(line):
                    vv = v[i*char_vertices_len:(i+1)*char_vertices_len]
                    i += 1 # TODO later i can ignore space character
                    g = font.glyph_map.get(ord(char), font.glyph_map.get(65533))
                    advance = g['advance'] * self.style.scale
                    plane_bounds = g.get('planeBounds')
                    atlas_bounds = g.get('atlasBounds')
                    if plane_bounds is None or atlas_bounds is None:
                        x_cursor += advance
                        continue
                    x0 = x_cursor + plane_bounds['left'] * self.style.scale
                    y0 = plane_bounds['bottom'] * self.style.scale
                    x1 = x_cursor + plane_bounds['right'] * self.style.scale
                    y1 = plane_bounds['top'] * self.style.scale
                    s0 = atlas_bounds['left'] / font.meta['atlas']['width']
                    s1 = atlas_bounds['right'] / font.meta['atlas']['width']
                    t1 = 1.0 - (atlas_bounds['top'] / font.meta['atlas']['height'])
                    t0 = 1.0 - (atlas_bounds['bottom'] / font.meta['atlas']['height'])

                    vv[0:9] = [x0, y0, 0.0, s0, t0, *color]
                    vv[10:19] = [x1, y0, 0.0, s1, t0, *color]
                    vv[20:29] = [x1, y1, 0.0, s1, t1, *color]
                    vv[30:39] = [x0, y0, 0.0, s0, t0, *color]
                    vv[40:49] = [x1, y1, 0.0, s1, t1, *color]
                    vv[50:59] = [x0, y1, 0.0, s0, t1, *color]

                    rotation_matrix = transformations.quaternion_matrix(self.layout.rotation)[:-1, :-1]
                    for j in range(0, vv.size, 10):
                        vv[j:j+3] = np.matmul(rotation_matrix, vv[j:j+3])
                    for j in range(0, vv.size, 10):
                        vv[j:j+3] += self.layout.position
                        vv[j+1] += y_cursor
                        vv[j+9] = self.layout.depth_offset_index + 2
                    x_cursor += advance
            y_cursor -= (self.line_height + self.line_gap)
            x_cursor = 0.0
        self.update_caret_rectangle()

    def update_visible_text(self, update_layout=True):
        if self.syntax_coloring:
            self.update_color_map()
        self.visible_lines = []
        self.input.set_num_lines(max(self.input.min_lines,
                                   min(self.input.max_lines, len(self.input.lines) + 1)))
        for i in range(self.input.scroll_offset[1], min(len(self.input.lines), self.input.scroll_offset[1]+self.input.num_lines)):
            line = self.input.lines[i]
            if not line:
                self.visible_lines.append(None)
            elif self.input.multiline and False:#self.input.wrap_lines:
                # TODO this can't work, need to expand lines before scroll offset is calculated. essentially this needs to be a step between caret location and scroll offset
                for j in range(0, len(line), self.input.chars_per_line):
                    visible_line = []
                    for k in range(j, min(len(line), j+self.input.chars_per_line)):
                        color = self.token_map[i][k] if self.syntax_coloring else self.style.color
                        visible_line.append((line[k], color))
                    self.visible_lines.append(visible_line)
            else:
                visible_line = []
                for k in range(self.input.scroll_offset[0], min(len(line), self.input.scroll_offset[0]+self.input.chars_per_line)):
                    color = self.token_map[i][k] if self.syntax_coloring and k in self.token_map[i] else self.style.color
                    visible_line.append((line[k], color))
                self.visible_lines.append(visible_line)

        self.visible_lines.extend([None] * (self.input.num_lines - len(self.visible_lines)))
        if self.handle:
            self.vector.delete(self.handle)
        chars_count = sum(len(x) if x else 0 for x in self.visible_lines)
        self.handle = self.vector.allocate(10 * 6 * chars_count)
        #self.layout.mark_measure_dirty()
        if update_layout:
            self.layout.mark_measure_dirty()

    def show_caret(self):
        self.caret_rectangle.show()
        self.caret_rectangle.update()

    def hide_caret(self):
        self.caret_rectangle.hide()
        self.caret_rectangle.update()

    def drop(self):
        self.layout.drop()
        self.caret_rectangle.drop()
        if self.handle:
            self.vector.delete(self.handle)
        self.dropped = True
