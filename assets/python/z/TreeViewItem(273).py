class TreeViewItem:
    def __init__(self, item=None, children=None,
                 expanded=True):
        self.item = item
        self.expanded = expanded
        self.children= children or []
