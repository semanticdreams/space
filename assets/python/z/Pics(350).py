import os
from OpenGL.GL import *
import numpy as np
from PIL import Image
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at


class Pics:
    def __init__(self):
        self.program = world.shaders.build_program(world.shaders.find_shader('pic.vert'),
                                                   world.shaders.find_shader('pic.frag'))

        self.projection_uniform = glGetUniformLocation(self.program, b'projection')
        self.view_uniform = glGetUniformLocation(self.program, b'view')

        self.vao = glGenVertexArrays(1)
        self.vbo = glGenBuffers(1)

        self.pics = []

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glEnableVertexAttribArray(0)
        glEnableVertexAttribArray(1)
        stride = 5 * 4
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, c_void_p(0))
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, c_void_p(4 * 3))

    def add_pic(self, pic):
        self.pics.append(pic)

    def remove_pic(self, pic):
        self.pics.remove(pic)

    def render(self, view, projection):
        glBindVertexArray(self.vao)

        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glUseProgram(self.program)

        glUniformMatrix4fv(self.projection_uniform, 1, GL_FALSE, projection)
        glUniformMatrix4fv(self.view_uniform, 1, GL_FALSE, view)

        glActiveTexture(GL_TEXTURE0)

        for pic in self.pics:
            if pic.vertices is not None:
                glBufferData(GL_ARRAY_BUFFER, 4 * len(pic.vertices), pic.vertices, GL_STREAM_DRAW)
                glBindTexture(GL_TEXTURE_2D, pic.texture_id)
                glDrawArrays(GL_TRIANGLES, 0, int(len(pic.vertices) / 5))