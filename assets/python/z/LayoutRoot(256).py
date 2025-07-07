class LayoutRoot:
    def __init__(self):
        self.measure_dirt = set()
        self.layout_dirt = set()

    def update(self):
        # TODO measure measure and layout duplication and optimize if prevalent
        for node in self.measure_dirt:
            n = node
            while n.parent and n.parent.uses_child_measures:
                n = n.parent
            n.measurer()
            self.layout_dirt.add(n)
        for node in self.layout_dirt:
            node.layouter()
        self.measure_dirt.clear()
        self.layout_dirt.clear()

    def drop(self):
        pass
