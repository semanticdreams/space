class PerlinTerrain:
    def __init__(self, width=300, length=300, position=None, scale=None, opacity=0.7):
        self.width = width
        self.length = length
        self.position = np.array(position) if position is not None else np.array([0, -100, 0])
        self.scale = np.array(scale) if scale is not None else np.array([5, 2, 5])
        self.opacity = opacity

        # Noise divisors and scales for mountains, boulders, rocks
        self.n1div, self.n2div, self.n3div = 30, 4, 1
        self.n1scale, self.n2scale, self.n3scale = 20, 2, 1
        self.zroot, self.zpower = 2, 2.5

        # Color map
        self.colors = {
            0: (0, 0, 1, 1),
            1: (1, 1, 0, 1),
            20: (0, 1, 0, 1),
            25: (0.5, 0.5, 0.5, 1),
            1000: (1, 1, 1, 1)
        }

        # Perlin noise generators
        self.noise1 = z.PerlinNoise(self.width / self.n1div, self.length / self.n1div)
        self.noise2 = z.PerlinNoise(self.width / self.n2div, self.length / self.n2div)
        self.noise3 = z.PerlinNoise(self.width / self.n3div, self.length / self.n3div)

        self.points = []
        self.triangles = []

        self.vertices = self._generate_triangles()
        self.triangle_vector = world.renderers.scene_triangle_vector
        self.handle = self.triangle_vector.allocate(self.vertices.size)
        self.update_positions()

    def _get_color(self, a, b, c):
        z = (self.points[a][1] + self.points[b][1] + self.points[c][1]) / 3
        for height in sorted(self.colors.keys()):
            if z <= height:
                return self.colors[height]
        return self.colors[max(self.colors.keys())]

    def _generate_triangles(self):
        # Generate terrain height points
        for x in range(-self.width // 2, self.width // 2):
            for y in range(-self.length // 2, self.length // 2):
                x1 = x + self.width / 2
                y1 = y + self.length / 2
                z = (
                    self.noise1.perlin(x1 / self.n1div, y1 / self.n1div) * self.n1scale +
                    self.noise2.perlin(x1 / self.n2div, y1 / self.n2div) * self.n2scale +
                    self.noise3.perlin(x1 / self.n3div, y1 / self.n3div) * self.n3scale
                )

                if z >= 0:
                    z = -math.sqrt(z)
                else:
                    z = ((-z) ** (1 / self.zroot)) ** self.zpower

                self.points.append([x, z, y])

        # Generate triangles and associated vertex data
        for x in range(self.width):
            for y in range(self.length):
                idx = x * self.length + y
                if x > 0 and y > 0:
                    a, b, c = idx, idx - 1, (x - 1) * self.length + y
                    self.triangles.append([a, b, c, self._get_color(a, b, c)])
                if x < self.width - 1 and y < self.length - 1:
                    a, b, c = idx, idx + 1, (x + 1) * self.length + y
                    self.triangles.append([a, b, c, self._get_color(a, b, c)])

        # Flatten vertex data
        vertices = []
        for a, b, c, color in self.triangles:
            for idx in (a, b, c):
                vertices.extend([*self.points[idx], *color, 0])
        return np.array(vertices, dtype=float)

    def update_positions(self):
        v = self.triangle_vector.view(self.handle)
        for i in range(0, self.vertices.size, 8):
            v[i:i+3] = self.vertices[i:i+3] * self.scale + self.position
            v[i+3:i+6] = self.vertices[i+3:i+6] / 5
            v[i+6] = self.opacity

    def get_physics(self):
        points = np.array(self.points) * self.scale #+ self.position
        triangle_mesh = bt.TriangleMesh()
        for tri in self.triangles:
            a, b, c, _ = tri
            triangle_mesh.addTriangle(
                bt.Vector3(*points[a]),
                bt.Vector3(*points[b]),
                bt.Vector3(*points[c]),
                True
            )
        terrain_shape = bt.BvhTriangleMeshShape(triangle_mesh, True)
        transform = bt.Transform()
        transform.setIdentity()
        transform.setOrigin(bt.Vector3(*self.position))
        motion_state = bt.DefaultMotionState(transform)
        terrain_body = bt.RigidBody(bt.RigidBodyConstructionInfo(
            0, motion_state, terrain_shape, bt.Vector3(0, 0, 0)
        ))
        return triangle_mesh, terrain_shape, motion_state, terrain_body

    def drop(self):
        self.triangle_vector.delete(self.handle)