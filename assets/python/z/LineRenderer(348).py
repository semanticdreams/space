from OpenGL.GL import *
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at


class LineRenderer:
    def __init__(self):
        self.program = world.shaders.build_program(world.shaders.find_shader('line.vert'),
                                                   world.shaders.find_shader('line.frag'))

        self.projection_uniform = glGetUniformLocation(self.program, b'projection')
        self.view_uniform = glGetUniformLocation(self.program, b'view')

        self.vao = glGenVertexArrays(1)
        self.vbo = glGenBuffers(1)

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glEnableVertexAttribArray(0)
        glEnableVertexAttribArray(1)
        stride = 6 * 4
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, c_void_p(0))
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, c_void_p(4 * 3))

    def render_lines(self, view, projection, data):
        glBindVertexArray(self.vao)

        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glBufferData(GL_ARRAY_BUFFER, 4*len(data), data,
                     GL_STREAM_DRAW)

        glUseProgram(self.program)

        glUniformMatrix4fv(self.projection_uniform, 1, GL_FALSE, projection)
        glUniformMatrix4fv(self.view_uniform, 1, GL_FALSE, view)

        glDrawArrays(GL_LINES, 0, int(len(data) / 6))

    def render_line_strips(self, view, projection, data):
        glBindVertexArray(self.vao)

        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glUseProgram(self.program)

        glUniformMatrix4fv(self.projection_uniform, 1, GL_FALSE, projection)
        glUniformMatrix4fv(self.view_uniform, 1, GL_FALSE, view)

        for item in data:
            glBufferData(GL_ARRAY_BUFFER, 4*len(item), item,
                     GL_STREAM_DRAW)
            glDrawArrays(GL_LINE_STRIP, 0, int(len(item) / 6))