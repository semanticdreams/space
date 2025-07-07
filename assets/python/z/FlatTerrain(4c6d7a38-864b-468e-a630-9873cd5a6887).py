import numpy as np

class FlatTerrain:
    def __init__(self, width=50, length=50, position=None, scale=None, opacity=1.0):
        self.width = width
        self.length = length
        self.position = np.array(position) if position is not None else np.array([-500, -100, -500])
        self.scale = np.array(scale) if scale is not None else np.array([20, 1, 20])
        self.opacity = opacity

        # Precompute vertices count:
        # Each square has 2 triangles, each triangle has 3 vertices -> 6 vertices per square
        num_squares = width * length
        num_vertices = num_squares * 6

        # Create the vertex array: (num_vertices, 8) -> [x, y, z, r, g, b, a, extra]
        self.vertices = np.zeros((num_vertices, 8), dtype=np.float32)

        self._generate_triangles()

        self.triangle_vector = world.renderers.scene_triangle_vector
        self.handle = self.triangle_vector.allocate(self.vertices.size)
        self.update_positions()

    def _generate_triangles(self):
        # Create grid coords for squares
        xs = np.arange(self.width)
        ys = np.arange(self.length)
        xs_grid, ys_grid = np.meshgrid(xs, ys, indexing='ij')  # shape (width, length)

        # Flatten for iteration
        xs_flat = xs_grid.flatten()
        ys_flat = ys_grid.flatten()

        # Compute base index for each square's 6 vertices in the big array
        base_idx = np.arange(xs_flat.size) * 6

        # Define relative coords for the two triangles per square
        # Triangle 1 vertices: a(x,y), b(x+1,y), c(x,y+1)
        tri1 = np.array([[0, 0], [1, 0], [0, 1]])
        # Triangle 2 vertices: b(x+1,y), d(x+1,y+1), c(x,y+1)
        tri2 = np.array([[1, 0], [1, 1], [0, 1]])

        # Precompute positions for all vertices
        # For each square, we have 6 vertices (2 triangles)
        vertices_xy = np.concatenate((tri1, tri2), axis=0)  # shape (6,2)

        # Repeat for all squares
        all_offsets = (vertices_xy[np.newaxis, :, :] +
                       np.stack((xs_flat[:, np.newaxis], ys_flat[:, np.newaxis]), axis=2)).reshape(-1, 2)

        # Set vertex positions: x, y, z
        self.vertices[:, 0] = all_offsets[:, 0]  # x
        self.vertices[:, 1] = 0                   # y (flat)
        self.vertices[:, 2] = all_offsets[:, 1]  # z

        # Compute colors: checkerboard pattern for each square, repeated 6 times per square
        # For color indexing, use the (x + y) of the square, not vertex coords
        checker = (xs_flat + ys_flat) % 2  # 0 or 1 for each square
        colors_dark = np.array([0.3, 0.3, 0.3, 1.0], dtype=np.float32)
        colors_light = np.array([0.7, 0.7, 0.7, 1.0], dtype=np.float32)

        # Repeat color 6 times per square (6 vertices)
        colors = np.where(checker[:, None], colors_light, colors_dark)  # shape (num_squares, 4)
        colors_repeated = np.repeat(colors, 6, axis=0)                   # shape (num_vertices, 4)

        # Set color components
        self.vertices[:, 3:7] = colors_repeated

        # Extra attribute (set to zero)
        self.vertices[:, 7] = 0

    def update_positions(self):
        v = self.triangle_vector.view(self.handle).reshape(-1, 8)
        # Scale and translate positions (x, y, z)
        v[:, :3] = self.vertices[:, :3] * self.scale + self.position
        # Copy colors (r, g, b, a) as-is from precomputed vertices
        v[:, 3:7] = self.vertices[:, 3:7]
        # Set opacity (override alpha channel)
        v[:, 6] = self.opacity

    def drop(self):
        self.triangle_vector.delete(self.handle)