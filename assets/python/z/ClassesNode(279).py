class ClassesNode(z.DynamicGraphNode):
    def __init__(self):
        super().__init__(key='classes', label='classes',
                         color=(0.8, 0.2, 0, 1),
                         sub_color=(0.8, 0.2, 0, 1),
                         view=z.ClassesNodeView)
