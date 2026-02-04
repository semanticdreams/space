class StartNode(z.DynamicGraphNode):
    def __init__(self):
        super().__init__(
            key='start', label='start',
            color=(0, 1, 0, 1),
            sub_color=(0, 1, 0, 1),
            view=z.StartNodeView)
