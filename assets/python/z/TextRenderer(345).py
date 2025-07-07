import json
import os
from OpenGL.GL import *
from PIL import Image
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at


class TextRenderer:
    def __init__(self):
        self.program = world.shaders.build_program(world.shaders.find_shader('msdf.vert'),
                                                   world.shaders.find_shader('msdf.frag'))
        self.projection_uniform = glGetUniformLocation(self.program, b'projection')
        self.view_uniform = glGetUniformLocation(self.program, b'view')
        self.pxrange_uniform = glGetUniformLocation(self.program, b'pxRange')

        self.vao, self.vbo = self.create_buffers()

    def create_buffers(self):
        vao = glGenVertexArrays(1)
        vbo = glGenBuffers(1)
        glBindVertexArray(vao)
        glBindBuffer(GL_ARRAY_BUFFER, vbo)

        stride = 10 * sizeof(c_float)

        # Position attribute
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, None)

        # UV attribute
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, c_void_p(3 * sizeof(c_float)))

        # Color attribute
        glEnableVertexAttribArray(2)
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, stride, c_void_p(5 * sizeof(c_float)))

        # depth offset index
        glEnableVertexAttribArray(3)
        glVertexAttribPointer(3, 1, GL_INT, GL_FALSE, stride, c_void_p(9 * sizeof(c_float)))

        #glBindBuffer(GL_ARRAY_BUFFER, 0)
        #glBindVertexArray(0)
        return vao, vbo

    def render(self, view_matrix, projection_matrix, data, font):
        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        #array = np.array(self.text_vertices, np.float32)
        glBufferData(GL_ARRAY_BUFFER, data.nbytes, data, GL_STREAM_DRAW)

        glUseProgram(self.program)

        glUniformMatrix4fv(self.projection_uniform, 1, GL_FALSE, projection_matrix)
        glUniformMatrix4fv(self.view_uniform, 1, GL_FALSE, view_matrix)
        glUniform1f(self.pxrange_uniform, font.meta['atlas']['distanceRange'])

        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, font.texture)
        #glUniform1i(glGetUniformLocation(self.program, "msdf"), 0)

        glDrawArrays(GL_TRIANGLES, 0, int(len(data) / 10))

        glBindVertexArray(0)
        glUseProgram(0)
