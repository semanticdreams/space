class FocusNode:
    def __init__(self, obj=None, on_changed=None, on_subtree_changed=None, parent=None):
        self.obj = obj
        self.on_changed = on_changed or (lambda v: None)
        self.on_subtree_changed = on_subtree_changed or (lambda v: None)
        self.parent = parent
        self.children = []

    def __str__(self):
        return f'<FocusNode: {self.obj}>'

    def __repr__(self):
        return str(self)

    def disconnect(self):
        self.on_changed = lambda v: None
        self.on_subtree_changed = lambda v: None

    def dump(self, indent=0):
        print(' ' * indent + ('*' if world.focus.current == self else '') + str(self))
        for child in self.children:
            child.dump(indent + 2)

    def has_current_descendant(self):
        if world.focus.current == self:
            return True
        for child in self.children:
            if child.has_current_descendant():
                return True
        return False

    # for legacy compat
    def add_child(self, obj, on_changed=None, on_subtree_changed=None):
        return world.focus.create_node(obj, on_changed, on_subtree_changed=on_subtree_changed, parent=self)

    # for legacy compat
    def drop(self):
        world.focus.drop_node(self)