class TextSpan:
    def __init__(self, text=None, codepoints=None, style=None, hud=False):
        self.hud = hud
        self.codepoints = codepoints if text is None else [ord(c) for c in text]
        self.style = style or z.TextStyle()
        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter, name='text-span')
        if self.hud:
            self.vector = world.renderers.get_hud_text_vector(self.style.font)
        else:
            self.vector = world.renderers.get_scene_text_vector(self.style.font)
        self.handle = None

        self.glyph_positions = []
        self.glyph_advances = []

        self.dirty = {'text'}
        self.update_text()

    def set_hud(self, hud):
        if hud != self.hud:
            if self.handle:
                self.vector.delete(self.handle)
                self.handle = None
            if hud:
                self.vector = world.renderers.get_hud_text_vector(self.style.font)
            else:
                self.vector = world.renderers.get_scene_text_vector(self.style.font)
            self.dirty.add('text')
            self.update_text()

        self.hud = hud

    def set_text(self, text, mark_layout_measure_dirty=True):
        self.codepoints = [ord(c) for c in text]
        self.dirty.add('text')
        self.update_text()
        if mark_layout_measure_dirty:
            self.layout.mark_measure_dirty()

    def update_text(self):
        if 'text' in self.dirty:
            if self.handle:
                self.vector.delete(self.handle)
            self.handle = self.vector.allocate(10 * 6 * len(self.codepoints))
            self.dirty.remove('text')

    def measurer(self):
        font = self.style.font
        #self.update_text()
        self.layout.measure = np.array((0, 0, 0), float)
        self.layout.measure[1] = (font.meta['metrics']['ascender'] - font.meta['metrics']['descender']) \
                * self.style.scale
        for i, c in enumerate(self.codepoints):
            g = font.glyph_map.get(c, font.glyph_map.get(65533))
            advance = g['advance'] * self.style.scale
            self.layout.measure[0] += advance

    def layouter(self):
        font = self.style.font
        char_vertices_len = 10 * 6
        x_cursor = 0.0
        v = self.vector.view(self.handle)
        self.glyph_positions.clear()
        self.glyph_advances.clear()
        for i, c in enumerate(self.codepoints):
            vv = v[i*char_vertices_len:(i+1)*char_vertices_len]
            g = font.glyph_map.get(c, font.glyph_map.get(65533))
            advance = g['advance'] * self.style.scale
            self.glyph_advances.append(advance)
            plane_bounds = g.get('planeBounds')
            atlas_bounds = g.get('atlasBounds')

            # Handle space character separately (no plane or atlas bounds, just advance)
            if plane_bounds is None or atlas_bounds is None:
                self.glyph_positions.append(self.layout.position + transformations.rotate_vector(self.layout.rotation, np.array([x_cursor, 0, 0], float)))
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

            vv[0:9] = [x0, y0, 0.0, s0, t0, *self.style.color]
            vv[10:19] = [x1, y0, 0.0, s1, t0, *self.style.color]
            vv[20:29] = [x1, y1, 0.0, s1, t1, *self.style.color]
            vv[30:39] = [x0, y0, 0.0, s0, t0, *self.style.color]
            vv[40:49] = [x1, y1, 0.0, s1, t1, *self.style.color]
            vv[50:59] = [x0, y1, 0.0, s0, t1, *self.style.color]

            # apply rotation
            rotation_matrix = transformations.quaternion_matrix(self.layout.rotation)[:-1, :-1]
            for j in range(0, vv.size, 10):
                vv[j:j+3] = np.matmul(rotation_matrix, vv[j:j+3])

            # apply position
            for j in range(0, vv.size, 10):
                vv[j:j+3] += self.layout.position
                vv[j+9] = self.layout.depth_offset_index

            self.glyph_positions.append(np.array(vv[j:j+3]))
            #x += self.glyph_sizes[i][0]
            x_cursor += advance

    def get_char_position(self, i):
        return self.glyph_positions[i]

    def get_char_size(self, i):
        return self.glyph_sizes[i]

    def drop(self):
        self.vector.delete(self.handle)
        self.layout.drop()
