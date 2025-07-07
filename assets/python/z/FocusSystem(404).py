class FocusSystem:
    def __init__(self):
        self.root = z.FocusNode()
        self.current = None
        world.focus = self

    def dump(self):
        self.root.dump()

    # for legacy compat
    def add_child(self, obj, on_changed=None, on_subtree_changed=None):
        return self.root.add_child(obj, on_changed, on_subtree_changed=on_subtree_changed)

    def create_node(self, obj=None, on_changed=None, on_subtree_changed=None, parent=None):
        parent = parent or self.root
        node = z.FocusNode(obj=obj,
                         on_changed=on_changed,
                         on_subtree_changed=on_subtree_changed,
                         parent=parent)
        parent.children.append(node)
        if parent == self.current:
            self.set_focus(node)
        if self.current is None:
            self.set_focus(node)
        return node

    def drop_node(self, node):
        assert not node.children, node.children
        node.parent.children.remove(node)
        if self.current == node:
            self.focus_nearest_root_child(node)
        if self.current == node:
            self.unfocus()

    def unfocus(self):
        if self.current:
            self.current.on_changed(False)
            while self.current:
                self.current.on_subtree_changed(False)
                self.current = self.current.parent

    def set_focus(self, node):
        assert node
        node = self.find_first_leaf(node)
        if self.current != node:
            if self.current:
                self.current.on_changed(False)
            n, node_ancestors = node, []
            while n:
                node_ancestors.append(n)
                n = n.parent
            i = len(node_ancestors) - 1
            while self.current:
                if self.current in node_ancestors:
                    i = node_ancestors.index(self.current)
                    break
                self.current.on_subtree_changed(False)
                self.current = self.current.parent
            for n in reversed(node_ancestors[:i]):
                n.on_subtree_changed(True)
            node.on_changed(True)
            self.current = node

    def find_first_leaf(self, node):
        # Helper method to find the first leaf in the subtree of the given node
        while node.children:
            node = node.children[0]
        return node

    def find_next_leaf(self, node):
        # Helper method to find the next leaf node in the tree
        while node.parent is not None:
            # Try to find a following sibling
            parent = node.parent
            index = parent.children.index(node)
            if index + 1 < len(parent.children):
                # If a following sibling exists, find its first leaf descendant
                return self.find_first_leaf(parent.children[index + 1])
            # If no following sibling, move up to the parent
            node = parent
        # If no next leaf found, return the first leaf of the entire tree
        return self.find_first_leaf(self.root)

    def find_last_leaf(self, node):
        # Helper method to find the last leaf in the subtree of the given node
        while node.children:
            node = node.children[-1]
        return node

    def find_previous_leaf(self, node):
        # Helper method to find the previous leaf node in the tree
        while node.parent is not None:
            parent = node.parent
            index = parent.children.index(node)
            if index > 0:
                # If a preceding sibling exists, find its last leaf descendant
                return self.find_last_leaf(parent.children[index - 1])
            # If no preceding sibling, move up to the parent
            node = parent
        # If no previous leaf found, return the last leaf of the entire tree
        return self.find_last_leaf(self.root)

    def focus_previous(self):
        if not self.current:
            return self.set_focus(self.root)
        self.set_focus(self.find_previous_leaf(self.current))

    def focus_next(self):
        if not self.current:
            return self.set_focus(self.root)
        self.set_focus(self.find_next_leaf(self.current))

    def focus_next_sibling(self, node):
        idx = node.parent.children.index(node)
        if idx + 1 < len(node.parent.children):
            self.set_focus(node.parent.children[idx + 1])

    def focus_previous_sibling(self, node):
        idx = node.parent.children.index(node)
        if idx > 0:
            self.set_focus(node.parent.children[idx - 1])

    def find_leaves(self):
        leaves = []
        stack = [self.root]
        while stack:
            node = stack.pop()
            if not node.children:
                leaves.append(node)
            else:
                stack.extend(reversed(node.children))
        return leaves

    def focus_left(self):
        if not self.current:
            return self.set_focus(self.root)

        nodes = [x for x in self.find_leaves() if x != self.current]

        # vectors from left edge of current obj to right edge of each candidate
        # centered on y and z axis
        # eventually need to align with camera instead
        vecs = [(x.obj.layout.position \
                 + np.array((x.obj.layout.size[0],
                             x.obj.layout.size[1] / 2,
                             x.obj.layout.size[2] / 2))) \
                - (self.current.obj.layout.position \
                   + np.array((0,
                               self.current.obj.layout.size[1] / 2,
                               self.current.obj.layout.size[2] / 2)))
                for x in nodes]

        # could just check sign of vecs[i][0] instead of computing angle
        candidates = [i for i, x in enumerate(vecs)
                      if util.angle_between_vectors([-1, 0, 0], vecs[i]) < 1.57]
        if candidates:
            idx = sorted(candidates,
                         key=lambda i: np.linalg.norm(vecs[i]),
                         reverse=False)[0]
            self.set_focus(nodes[idx])

    def focus_right(self):
        if not self.current:
            return self.set_focus(self.root)

        nodes = [x for x in self.find_leaves() if x != self.current]

        vecs = [(x.obj.layout.position \
                 + np.array((0,
                             x.obj.layout.size[1] / 2,
                             x.obj.layout.size[2] / 2))) \
                - (self.current.obj.layout.position \
                   + np.array((self.current.obj.layout.size[0],
                               self.current.obj.layout.size[1] / 2,
                               self.current.obj.layout.size[2] / 2)))
                for x in nodes]

        candidates = [i for i, x in enumerate(vecs)
                      if util.angle_between_vectors([1, 0, 0], vecs[i]) < 1.57]
        if candidates:
            idx = sorted(candidates,
                         key=lambda i: np.linalg.norm(vecs[i]),
                         reverse=False)[0]
            self.set_focus(nodes[idx])

    def focus_up(self):
        if not self.current:
            return self.set_focus(self.root)

        nodes = [x for x in self.find_leaves() if x != self.current]

        vecs = [(x.obj.layout.position \
                 + np.array((x.obj.layout.size[0] / 2,
                             0,
                             x.obj.layout.size[2] / 2))) \
                - (self.current.obj.layout.position \
                   + np.array((self.current.obj.layout.size[0] / 2,
                               self.current.obj.layout.size[1],
                               self.current.obj.layout.size[2] / 2)))
                for x in nodes]

        candidates = [i for i, x in enumerate(vecs)
                      if util.angle_between_vectors([0, 1, 0], vecs[i]) < 1.57]
        if candidates:
            idx = sorted(candidates,
                         key=lambda i: np.linalg.norm(vecs[i]),
                         reverse=False)[0]
            self.set_focus(nodes[idx])

    def focus_down(self):
        if not self.current:
            return self.set_focus(self.root)

        nodes = [x for x in self.find_leaves() if x != self.current]

        vecs = [(x.obj.layout.position \
                 + np.array((x.obj.layout.size[0] / 2,
                             x.obj.layout.size[1],
                             x.obj.layout.size[2] / 2))) \
                - (self.current.obj.layout.position \
                   + np.array((self.current.obj.layout.size[0] / 2,
                               0,
                               self.current.obj.layout.size[2] / 2)))
                for x in nodes]

        candidates = [i for i, x in enumerate(vecs)
                      if util.angle_between_vectors([0, -1, 0], vecs[i]) < 1.57]
        if candidates:
            idx = sorted(candidates,
                         key=lambda i: np.linalg.norm(vecs[i]),
                         reverse=False)[0]
            self.set_focus(nodes[idx])

    def focus_nearest_root_child(self, node):
        candidates = self.root.children
        if candidates:
            nearest = sorted(candidates,
                             key=lambda x: np.linalg.norm(x.obj.layout.position \
                                                          - node.obj.layout.position))[0]
            self.set_focus(nearest)

    def drop(self):
        pass
