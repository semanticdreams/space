class Layout(z.Droppable):
    @staticmethod
    def parse_axis(s):
        return {'x': 0, 'y': 1, 'z': 2}.get(s, s)

    @staticmethod
    def parse_axes(axes):
        return tuple(Layout.parse_axis(axis) for axis in axes)

    def __init__(self, children=None, measurer=None, layouter=None,
                 uses_child_measures=True, name=None, intersect=None):
        self.dropped = False
        self.uses_child_measures = uses_child_measures
        self.parent = None
        self.root = None
        self.name = name
        self.children = []
        self.position = np.array((0, 0, 0), float)
        self.rotation = np.array((1, 0, 0, 0), float)
        self.measure = np.array((0, 0, 0), float)
        self.size = np.array((0, 0, 0), float)
        self.depth_offset_index = 0
        self.measure_dirty = False
        self.layout_dirty = False

        self.measurer = measurer
        self.layouter = layouter

        if intersect:
            self.intersect = intersect

        self.set_children(children or [])

    def __str__(self):
        return f'Layout({self.name})'

    def dump(self, indent=0):
        print(' ' * indent, self.name, self.position, self.size)
        for child in self.children:
            child.dump(indent + 1)

    def set_children(self, children):
        self.clear_children()
        self.add_children(children)

    def clear_children(self):
        if self.children:
            for child in list(self.children):
                self.remove_child(child)

    def add_children(self, children):
        for child in children:
            self.add_child(child)

    def add_child(self, child):
        child.parent = self
        child.set_root(self.root)
        self.children.append(child)

    def remove_child(self, child):
        child.parent = None
        child.set_root(None)
        self.children.remove(child)

    def set_position(self, position):
        self.position = position
        self.mark_layout_dirty()

    def get_position(self):
        return self.position

    def get_rotation(self):
        return self.rotation

    def set_rotation(self, rotation):
        self.rotation = rotation
        self.mark_layout_dirty()

    def set_root(self, root):
        stack = [self]
        while stack:
            node = stack.pop()
            stack.extend(node.children)
            if root:
                if node.measure_dirty:
                    root.measure_dirt.add(node)
                    node.measure_dirty = False
                if node.layout_dirty:
                    root.layout_dirt.add(node)
                    node.layout_dirty = False
            elif node.root:
                node.root.measure_dirt.discard(node)
                node.root.layout_dirt.discard(node)
            node.root = root


    def mark_layout_dirty(self):
        if self.root:
            self.root.layout_dirt.add(self)
        else:
            self.layout_dirty = True

    def mark_measure_dirty(self):
        if self.root:
            self.root.measure_dirt.add(self)
        else:
            self.measure_dirty = True

    def drop(self):
        self.clear_children()
        if self.root:
            self.root.measure_dirt.discard(self)
            self.root.layout_dirt.discard(self)
        self.dropped = True

    def intersect(self, ray):
        # Get the rotation matrix from the quaternion and remove the translation part
        rotation_matrix = transformations.quaternion_matrix(self.rotation)[:-1, :-1]
        inverse_rotation_matrix = np.linalg.inv(rotation_matrix)

        # Transform the ray's origin and direction into the local space of the object
        ray_origin_local = np.dot(inverse_rotation_matrix, ray.origin - self.position)
        ray_direction_local = np.dot(inverse_rotation_matrix, ray.direction)

        # The AABB's bounds in local coordinates (since the object's position is at the bottom-left corner)
        # The size in local space is now a 3D vector
        min_bounds = np.array([0, 0, 0])  # Bottom-left-front corner at the origin
        max_bounds = np.array([self.size[0], self.size[1], self.size[2]])  # Full width, height, and depth

        tmin, tmax = -np.inf, np.inf

        # Traverse through each axis (x, y, z)
        for i in range(3):  # x, y, z axes
            # If the ray direction along the axis is non-zero, calculate intersections
            if ray_direction_local[i] != 0:
                t1 = (min_bounds[i] - ray_origin_local[i]) / ray_direction_local[i]
                t2 = (max_bounds[i] - ray_origin_local[i]) / ray_direction_local[i]

                # Ensure t1 is the smaller and t2 is the larger value
                if t1 > t2:
                    t1, t2 = t2, t1

                # Update tmin and tmax
                tmin = max(tmin, t1)
                tmax = min(tmax, t2)

                # If tmin > tmax, there is no intersection
                if tmin > tmax:
                    return False, None, None

        # If we pass all checks, compute the intersection point and the distance
        intersection_point_local = ray_origin_local + tmin * ray_direction_local

        # Adjust the intersection point to account for the object's position in world coordinates
        intersection_point_world = np.dot(rotation_matrix, intersection_point_local) + self.position

        # Compute the distance from the ray origin to the intersection point
        distance = np.linalg.norm(intersection_point_world - ray.origin)

        return True, intersection_point_world, distance
