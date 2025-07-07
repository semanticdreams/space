from util import normalize


class Camera:
    #__slots__ = 'position', 'rotation', 'view_matrix', 'dirty', 'changed'

    def __init__(self, position, rotation):
        self.position = np.asarray(position, float)
        self.rotation = np.asarray(rotation, float)

        self.view_matrix = None

        self.changed = z.Signal()

        self.dirty = {'position', 'rotation'}

    def forward(self, x):
        #v = np.array((0.0, 0.0, 0.0, 1.0), float)
        #v = transformations.quaternion_multiply(
        #    transformations.quaternion_multiply(self.rotation, v),
        #    transformations.quaternion_conjugate(self.rotation))
        self.position += self.get_forward() * x
        self.dirty.add('position')

    def right(self, x):
        #v = np.array((0.0, 1.0, 0.0, 0.0), float)
        #v = transformations.quaternion_multiply(
        #    transformations.quaternion_multiply(self.rotation, v),
        #    transformations.quaternion_conjugate(self.rotation))
        #self.position += v[1:] * x
        self.position += self.get_right() * x
        self.dirty.add('position')

    def up(self, x):
        #v = np.array((0.0, 0.0, 1.0, 0.0), float)
        #v = transformations.quaternion_multiply(
        #    transformations.quaternion_multiply(self.rotation, v),
        #    transformations.quaternion_conjugate(self.rotation))
        self.position += self.get_up() * x
        self.dirty.add('position')

    def yaw(self, angle):
        q = transformations.quaternion_about_axis(angle, [0, 1, 0])
        q = transformations.quaternion_multiply(q, self.rotation)
        q = q / np.linalg.norm(q)
        self.rotation = q
        self.dirty.add('rotation')

    def pitch(self, angle):
        q = transformations.quaternion_about_axis(angle, [1, 0, 0])
        q = transformations.quaternion_multiply(self.rotation, q)
        q = q / np.linalg.norm(q)
        self.rotation = q
        self.dirty.add('rotation')

    def roll(self, angle):
        q = transformations.quaternion_about_axis(angle, [0, 0, 1])
        q = transformations.quaternion_multiply(self.rotation, q)
        q = q / np.linalg.norm(q)
        self.rotation = q
        self.dirty.add('rotation')

    def get_right(self):
        return transformations.rotate_vector(
            self.rotation, np.array((1, 0, 0), float))
        #x = transformations.quaternion_multiply(
        #    self.rotation, np.array((1.0, 0, 0, 0)))
        #x = x / np.linalg.norm(x)
        #return x[:3]

    def get_up(self):
        return transformations.rotate_vector(
            self.rotation, np.array((0, 1, 0), float))
        #x = transformations.quaternion_multiply(
        #    self.rotation, np.array((0.0, 1.0, 0, 0)))
        #x = x / np.linalg.norm(x)
        #return x[:3]

    def get_forward(self):
        return transformations.rotate_vector(
            self.rotation, np.array((0, 0, -1), float))
        #x = transformations.quaternion_multiply(
        #    self.rotation, np.array((0.0, 0.0, -1.0, 0)))
        #x = x / np.linalg.norm(x)
        #return x[:3]

    def get_ahead_position(self, distance):
        return self.position + self.get_forward() * distance

    def get_forward_ray(self):
        return Ray(self.position, self.get_forward())

    def set_position(self, position):
        self.position = np.asarray(position, float)
        self.dirty.add('position')

    def set_rotation(self, rotation):
        self.rotation = np.asarray(rotation, float)
        self.dirty.add('rotation')

    def look_at(self, target):
        target = np.asarray(target, float)
        forward = normalize(self.position - target)
        global_up = np.array([0, 1, 0], float)
        right = np.cross(global_up, forward)
        up = np.cross(forward, right)

        rotation_matrix = transformations.identity_matrix()
        rotation_matrix[0, :3] = right
        rotation_matrix[1, :3] = up
        rotation_matrix[2, :3] = forward

        self.set_rotation(
            transformations.quaternion_from_matrix(
                transformations.inverse_matrix(rotation_matrix)))

    def approach(self, target, closeness=50):
        p = target.position.copy()
        p[0] += target.size[0] / 2
        p[1] += target.size[1] / 2
        center = p.copy()
        p[2] += closeness
        self.set_position(p)
        self.look_at(center)

    def update(self):
        if self.dirty:
            position_matrix = transformations.translation_matrix(self.position)
            rotation_matrix = transformations.quaternion_matrix(self.rotation)
            camera_matrix = transformations.concatenate_matrices(
                position_matrix, rotation_matrix
            )
            self.view_matrix = transformations.inverse_matrix(camera_matrix) \
                    .astype(float).flatten('F')
            self.dirty.clear()
            self.changed.emit()

    def get_view_matrix(self):
        self.update()
        return self.view_matrix
