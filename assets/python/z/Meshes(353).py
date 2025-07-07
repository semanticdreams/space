from OpenGL.GL import *
import numpy as np
from PIL import Image
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at


class Meshes:
    def __init__(self):
        self.meshes = []

        self.program = world.shaders.build_program(world.shaders.find_shader('mesh.vert'),
                                                   world.shaders.find_shader('mesh.frag'))

        self.projection_uniform = glGetUniformLocation(self.program, b'projection')
        self.view_uniform = glGetUniformLocation(self.program, b'view')

        self.vao = glGenVertexArrays(1)
        self.vbo = glGenBuffers(1)

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glEnableVertexAttribArray(0)
        glEnableVertexAttribArray(1)
        glEnableVertexAttribArray(2)
        stride = 8 * 4
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, c_void_p(0))
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, c_void_p(4 * 2))
        glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, stride, c_void_p(4 * 5))

    def render(self, view, projection):
        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glUseProgram(self.program)

        glUniformMatrix4fv(self.projection_uniform, 1, GL_FALSE, projection)
        glUniformMatrix4fv(self.view_uniform, 1, GL_FALSE, view)

        glActiveTexture(GL_TEXTURE0)

        for mesh in self.meshes:
            glBufferData(GL_ARRAY_BUFFER, 4 * len(mesh.data), mesh.data,
                     GL_STREAM_DRAW)
            glBindTexture(GL_TEXTURE_2D, mesh.texture)
            glDrawArrays(GL_TRIANGLES, 0, int(len(mesh.data) / 8))

    def create_mesh(self, vertices, texture_image):
        mesh = Mesh(vertices, texture_image)
        self.meshes.append(mesh)
        return mesh