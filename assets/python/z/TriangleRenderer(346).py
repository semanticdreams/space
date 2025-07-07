from OpenGL.GL import *
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at


class TriangleRenderer:
    def __init__(self):
        self.program = world.shaders.build_program(world.shaders.find_shader('triangle.vert'),
                                                   world.shaders.find_shader('triangle.frag'))

        self.projection_uniform = glGetUniformLocation(self.program, b'projection')
        self.view_uniform = glGetUniformLocation(self.program, b'view')

        self.viewpos_uniform = glGetUniformLocation(self.program, b'viewPos')
        self.dirlight_direction_uniform = glGetUniformLocation(self.program, b'dirLight.direction')
        self.dirlight_ambient_uniform = glGetUniformLocation(self.program, b'dirLight.ambient')
        self.dirlight_diffuse_uniform = glGetUniformLocation(self.program, b'dirLight.diffuse')
        self.dirlight_specular_uniform = glGetUniformLocation(self.program, b'dirLight.specular')

        glUseProgram(self.program)
        glUniform3f(self.dirlight_direction_uniform, 0.5, 0.2, 1.0)
        glUniform3f(self.dirlight_ambient_uniform, 0.4, 0.4, 0.4)
        glUniform3f(self.dirlight_diffuse_uniform, 0.6, 0.6, 0.6)
        glUniform3f(self.dirlight_specular_uniform, 1.0, 1.0, 1.0)

        self.vao = glGenVertexArrays(1)
        self.vbo = glGenBuffers(1)

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glEnableVertexAttribArray(0)
        glEnableVertexAttribArray(1)
        glEnableVertexAttribArray(2)
        stride = 8 * 4
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, c_void_p(0))
        glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, stride, c_void_p(4 * 3))
        glVertexAttribPointer(2, 1, GL_INT, GL_FALSE, stride, c_void_p(4 * 7))

    def render(self, view, projection, data, camera_position):
        glBindVertexArray(self.vao)

        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glBufferData(GL_ARRAY_BUFFER, data.nbytes, data,
                     GL_STREAM_DRAW)

        glUseProgram(self.program)

        glUniformMatrix4fv(self.projection_uniform, 1, GL_FALSE, projection)
        glUniformMatrix4fv(self.view_uniform, 1, GL_FALSE, view)

        cp = camera_position
        glUniform3f(self.viewpos_uniform, cp[0], cp[1], cp[2])

        glDrawArrays(GL_TRIANGLES, 0, int(len(data) / 8))
