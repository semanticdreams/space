class DynamicGraphNode:
    def __init__(self, key=None, label='',
                 color=(0.5, 0.5, 0.5, 1),
                 sub_color=(0.5, 0.5, 0.5, 1),
                 view=None):
        self.key = key
        self.label = label
        self.color = np.asarray(color, float)
        self.sub_color = np.asarray(sub_color, float)
        self.view = view
        self.changed = z.Signal()
        self.changed.connect(self.__on_changed)
        self.dynamic_graph = None

    def __on_changed(self):
        if self.dynamic_graph:
            self.dynamic_graph.node_changed(self)

    def get_edges(self):
        return []

    def set_sub_color(self, color):
        self.sub_color = np.asarray(color, float)

    def mount(self, dynamic_graph):
        self.dynamic_graph = dynamic_graph

    def unmount(self):
        self.dynamic_graph = None

    def drop(self):
        self.changed.disconnect(self.__on_changed)
