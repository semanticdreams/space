class FlexChild:
    def __init__(self, layout, flex=0, expanded=None):
        self.layout = layout
        self.flex = flex
        #self.expanded = expanded if expanded is not None else (True if flex else False)