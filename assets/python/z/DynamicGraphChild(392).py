class DynamicGraphChild:
    def __init__(self, dynamic_graph, node):
        self.dynamic_graph = dynamic_graph
        self.node = node
        self.key = self.node.key
        self.node.builder(self.dynamic_graph.builder_context)
        self.dialog = z.Dialog(self.key, self.node, on_inspector=self.on_inspector)
        self.dialog.closed.connect(lambda: self.dynamic_graph.drop_child(self))
        self.layout = self.dialog.layout

    def on_inspector(self):
        inspector = z.InspectorNode(self.node)
        self.dynamic_graph.add_children(self.node.key, [inspector])

    def get_position(self):
        return self.layout.position

    def set_position(self, position):
        self.layout.position = position
        self.layout.mark_layout_dirty()
        self.dynamic_graph.update_lines()

    def set_rotation(self, rotation):
        self.layout.rotation = rotation
        self.layout.mark_layout_dirty()

    def intersect(self, ray):
        return self.layout.intersect(ray)

    def drop(self):
        self.dialog.drop()
        self.node.drop()
