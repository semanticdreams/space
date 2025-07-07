from OpenGL.GL import *
from PIL import Image
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at


class Points:
    def __init__(self):
        glEnable(GL_PROGRAM_POINT_SIZE)

        self.program = world.shaders.build_program(world.shaders.find_shader('point.vert'),
                                                   world.shaders.find_shader('point.frag'))

        self.vector = z.Vector()
        self.needs_buffer_update = True

        self.projection_uniform = glGetUniformLocation(self.program, b'projection')
        self.view_uniform = glGetUniformLocation(self.program, b'view')

        self.vao = glGenVertexArrays(1)
        self.vbo = glGenBuffers(1)

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 32, ctypes.c_void_p(0))
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, 32, ctypes.c_void_p(12))
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE, 32, ctypes.c_void_p(28))
        glEnableVertexAttribArray(2)

    def create_point(self, position=(0, 0, 0), color=(1, 0, 0, 1), size=10):
        h = self.vector.allocate(8)
        v = self.vector.view(h)
        v[0:3] = np.asarray(position, float)
        v[3:7] = np.asarray(color, float)
        v[7] = float(size)
        self.needs_buffer_update = True
        return h

    def update_point(self, h, position=None, color=None, size=None):
        v = self.vector.view(h)
        if position is not None:
            v[0:3] = np.asarray(position, float)
        if color is not None:
            v[3:7] = np.asarray(color, float)
        if size is not None:
            v[7] = float(size)
        self.needs_buffer_update = True

    def destroy_point(self, h):
        self.vector.delete(h)
        self.needs_buffer_update = True

    def drop_point(self, h):
        self.destroy_point(h)

    def render(self, view, projection):
        if self.vector.array.size == 0:
            return
        glBindVertexArray(self.vao)

        if self.needs_buffer_update:
            glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
            glBufferData(GL_ARRAY_BUFFER, self.vector.array.nbytes, self.vector.array, GL_STATIC_DRAW)
            self.needs_buffer_update = False

        glUseProgram(self.program)

        glUniformMatrix4fv(self.projection_uniform, 1, GL_FALSE, projection)
        glUniformMatrix4fv(self.view_uniform, 1, GL_FALSE, view)

        glDrawArrays(GL_POINTS, 0, int(len(self.vector.array) / 8))
