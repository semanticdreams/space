class Flex:
    def __init__(self, children, axis='x', reverse=None,
                 xspacing=0.5, yspacing=0.5, zspacing=0.5,
                 xalign='start', yalign='start', zalign='start',
                 name=None):
        self.name = name
        self.axis = z.Layout.parse_axis(axis)
        self.cross_axes = tuple(x for x in range(3) if x != self.axis)
        self.spacing = np.array((xspacing, yspacing, zspacing), float)
        self.children = children
        self.reverse = reverse if reverse is not None else (True if self.axis == 1 else False)
        self.alignment = (xalign, yalign, zalign)
        for child in self.children:
            assert isinstance(child, z.FlexChild), type(child)
        self.layout = z.Layout(children=[x.layout for x in self.children],
                             measurer=self.measurer, layouter=self.layouter, name='flex')

    def measurer(self):
        if self.layout.children:
            [x.measurer() for x in self.layout.children]
            for axis in range(3):
                if self.axis == axis:
                    self.layout.measure[axis] = sum(x.measure[axis] for x in self.layout.children) \
                            + self.spacing[axis] * (len(self.layout.children) - 1)
                else:
                    self.layout.measure[axis] = max(x.measure[axis] for x in self.layout.children)

    def layouter(self):
        flex_sum = sum(x.flex for x in self.children)
        remaining = self.layout.size[self.axis] - self.spacing[self.axis] * (len(self.children) - 1)
        for child in self.children:
            if child.flex == 0:
                child.layout.size[self.axis] = child.layout.measure[self.axis]
                remaining -= child.layout.size[self.axis]
        if flex_sum:
            flex_base = remaining / flex_sum
            for child in self.children:
                if child.flex:
                    flex_base = max(flex_base, child.layout.measure[self.axis] / child.flex)
            for child in self.children:
                if child.flex:
                    child.layout.size[self.axis] = child.flex * flex_base
                    remaining -= child.layout.size[self.axis]
        offset = 0
        for child in self.children:
            for a in self.cross_axes:
                if self.alignment[a] == 'largest':
                    child.layout.size[a] = self.layout.size[a]
                else:
                    child.layout.size[a] = child.layout.measure[a]
            child.layout.rotation = self.layout.rotation.copy()
            child_position = np.array((0, 0, 0), float)
            child_position[self.axis] += self.layout.size[self.axis] \
                    - offset - child.layout.size[self.axis] \
                    if self.reverse else offset
            for a in self.cross_axes:
                if self.alignment[a] == 'center':
                    child_position[a] += (self.layout.size[a] - child.layout.size[a]) / 2
                elif self.alignment[a] == 'end':
                    child_position[a] += self.layout.size[a] - child.layout.size[a]

            child.layout.position = self.layout.position + transformations.rotate_vector(
                child.layout.rotation, child_position)
            child.layout.depth_offset_index = self.layout.depth_offset_index
            child.layout.layouter()
            offset += child.layout.size[self.axis] + self.spacing[self.axis]

    def set_children(self, children):
        self.children = children
        for child in self.children:
            assert isinstance(child, z.FlexChild), type(child)
        self.layout.set_children([x.layout for x in children])

    def clear_children(self):
        self.children = []
        self.layout.clear_children()

    def drop(self):
        self.layout.drop()
