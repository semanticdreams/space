import glob

import OpenGL
from OpenGL.GL import *
from PIL import Image

import numpy, math, sys, os


vertices = np.array([
    -1.0,  1.0, -1.0,
    -1.0, -1.0, -1.0,
     1.0, -1.0, -1.0,
     1.0, -1.0, -1.0,
     1.0,  1.0, -1.0,
    -1.0,  1.0, -1.0,

    -1.0, -1.0,  1.0,
    -1.0, -1.0, -1.0,
    -1.0,  1.0, -1.0,
    -1.0,  1.0, -1.0,
    -1.0,  1.0,  1.0,
    -1.0, -1.0,  1.0,

     1.0, -1.0, -1.0,
     1.0, -1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0, -1.0,
     1.0, -1.0, -1.0,

    -1.0, -1.0,  1.0,
    -1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
     1.0, -1.0,  1.0,
    -1.0, -1.0,  1.0,

    -1.0,  1.0, -1.0,
     1.0,  1.0, -1.0,
     1.0,  1.0,  1.0,
     1.0,  1.0,  1.0,
    -1.0,  1.0,  1.0,
    -1.0,  1.0, -1.0,

    -1.0, -1.0, -1.0,
    -1.0, -1.0,  1.0,
     1.0, -1.0, -1.0,
     1.0, -1.0, -1.0,
    -1.0, -1.0,  1.0,
     1.0, -1.0,  1.0
])


class SkyboxRenderer:
    def __init__(self):
        self.program = world.shaders.build_program(world.shaders.find_shader('skybox.vert'),
                                                   world.shaders.find_shader('skybox.frag'))

        glUseProgram(self.program)

        self.load_texture()

        self.pMatrixUniform = glGetUniformLocation(self.program, b'projection')
        self.view_matrix_uniform = glGetUniformLocation(self.program, b'view')

        self.vertex_data = np.array(vertices, np.float32)

        self.vao = glGenVertexArrays(1)
        self.vbo = glGenBuffers(1)

        glBindVertexArray(self.vao)
        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)

        glEnableVertexAttribArray(0)
        stride = 3 * 4
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, None)

        glBufferData(GL_ARRAY_BUFFER, self.vertex_data.nbytes, 101 * self.vertex_data,
                     GL_STATIC_DRAW)

        self.set_skybox(world.settings.get_value('skybox/path'), save=False)

    def set_skybox(self, path, save=True):
        if save:
            world.settings.set_value('skybox/path', path)
        if path is None:
            self.active = False
            return
        l = ['right', 'left', 'top', 'bottom', 'back', 'front']
        files = [glob.glob(f'{path}/{x}.*')[0] for x in l]
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_CUBE_MAP, self.texture_id)
        for i, filename in enumerate(files):
            img = Image.open(filename)
            #img = Image.open(filename).rotate(180).transpose(Image.FLIP_LEFT_RIGHT)
            mode = GL_RGB if img.mode == 'RGB' else GL_RGBA
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, mode, img.size[0], img.size[1],
                         0, mode, GL_UNSIGNED_BYTE, np.asanyarray(img))
        glBindTexture(GL_TEXTURE_CUBE_MAP, 0)
        self.active = True

    def load_texture(self):
        self.texture_id = glGenTextures(1)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_CUBE_MAP, self.texture_id)

        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)

        glBindTexture(GL_TEXTURE_CUBE_MAP, 0)

    def render(self):
        if not self.active:
            return
        glDepthMask(GL_FALSE)
        view_matrix = world.camera.camera.get_view_matrix().copy()
        view_matrix[12] = 0.0
        view_matrix[13] = 0.0
        view_matrix[14] = 0.0

        glBindVertexArray(self.vao)

        glUseProgram(self.program)

        glUniformMatrix4fv(self.pMatrixUniform, 1, GL_FALSE, world.projection.value)
        glUniformMatrix4fv(self.view_matrix_uniform, 1, GL_FALSE, view_matrix)

        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_CUBE_MAP, self.texture_id)

        glDrawArrays(GL_TRIANGLES, 0, int(len(self.vertex_data) / 3))

        glDepthMask(GL_TRUE)

    def drop(self):
        glDeleteTextures(1, self.texture_id)
