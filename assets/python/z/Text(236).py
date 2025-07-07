class Text:
    def __init__(self, text, hud=False, style=None, min_width=None):
        self.hud = hud
        self.style = style or z.TextStyle()
        self.min_width = min_width
        self.text = text
        self.spans = []
        self.layout = z.Layout([], measurer=self.measurer, layouter=self.layouter, name='text')
        self.dirty = {'text'}
        self.update_text()

    def set(self, text): # TODO tmp
        self.set_text(text)

    def set_hud(self, hud):
        for span in self.spans:
            span.set_hud(hud)
        self.hud = hud

    def set_text(self, text):
        self.text = text
        self.dirty.add('text')
        self.update_text()
        self.layout.mark_measure_dirty()

    def update_text(self):
        if 'text' in self.dirty:
            self.layout.clear_children() # TODO can this be avoided
            lines = self.text.split('\n')
            for span in self.spans[len(lines):]:
                span.drop()
            self.spans = self.spans[:len(lines)]
            for span, line in zip(self.spans, lines):
                span.set_text(line, mark_layout_measure_dirty=False)
            for line in lines[len(self.spans):]:
                self.spans.append(z.TextSpan(line, hud=self.hud, style=self.style))
            self.layout.set_children([x.layout for x in self.spans])
            self.dirty.remove('text')

    def measurer(self):
        #self.update_text()
        self.layout.measure = np.array((0, 0, 0), float)
        for child in self.layout.children:
            child.measurer()
            self.layout.measure[0] = max(self.layout.measure[0], child.measure[0])
            self.layout.measure[1] += child.measure[1]
        self.layout.measure[1] += 0.5 * (len(self.layout.children) - 1) # TODO should use font's linegap
        if self.min_width:
            self.layout.measure[0] = max(
                self.layout.measure[0],
                self.style.font.glyph_map[32]['advance'] * self.style.scale * self.min_width
            )

    def layouter(self):
        y = self.layout.measure[1]
        for child in self.layout.children:
            y -= child.measure[1]
            child.depth_offset_index = self.layout.depth_offset_index
            child.rotation = self.layout.rotation
            child.position = self.layout.position \
                    + transformations.rotate_vector(self.layout.rotation, np.array([0, y, 0], float))
            child.layouter()
            y -= 0.5 # TODO should use font's linegap

    def drop(self):
        self.layout.drop()
        for span in self.spans:
            span.drop()
