class StartNode(z.DynamicGraphNode):
    def __init__(self):
        super().__init__(
            key='start', label='start',
            color=(0, 1, 0, 1),
            sub_color=(0, 1, 0, 1),
            view=z.StartNodeView)

    #def get_edges(self):
    #    return [
    #        z.DynamicGraphEdge(source=self, target=z.ClassesNode()),
    #        z.DynamicGraphEdge(
    #            source=self,
    #            target=z.GraphEntityNode(world.apps['Entities'].get_entity('18'))
    #        ),
    #    ]
