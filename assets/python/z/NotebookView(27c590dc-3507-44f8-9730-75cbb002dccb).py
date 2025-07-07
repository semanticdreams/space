class NotebookView:
    def __init__(self, entity, focus_parent=world.focus):
        self.focus = focus_parent.add_child(self)
        self.entity = entity
        
    def drop(self):
        self.focus.drop()