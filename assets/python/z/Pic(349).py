import os
from OpenGL.GL import *
import numpy as np
from PIL import Image
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at


base_vertices = np.array([
    0, 0, 0,
    0, 1,
    0, 1, 0,
    0, 0,
    1, 1, 0,
    1, 0,
    1, 1, 0,
    1, 0,
    1, 0, 0,
    1, 1,
    0, 0, 0,
    0, 1
], np.float32)


class Pic:
    def __init__(self, image=None, filename=None):
        self.layout = z.Layout(measurer=self.measurer, layouter=self.layouter, name='pic')
        self.vertices = None

        if filename:
            image = Image.open(filename)

        mode = GL_RGBA if image.mode == 'RGBA' else GL_RGB

        self.image_size = image.size
        self.aspect = self.image_size[0] / self.image_size[1]

        data = np.array(list(image.getdata()), 'B')
        #data = np.array(image, dtype=np.uint8)
        self.texture_id = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, self.texture_id)
        glTexImage2D(GL_TEXTURE_2D, 0, mode, image.size[0], image.size[1],
                     0, mode, GL_UNSIGNED_BYTE, data)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)
        glBindTexture(GL_TEXTURE_2D, 0)

        world.renderers.pics.add_pic(self)

    def measurer(self):
        base_size = 30
        self.layout.measure = np.array((base_size, base_size / self.aspect, 0))

    def layouter(self):
        self.vertices = base_vertices.copy()
        rotation_matrix = transformations.quaternion_matrix(
            self.layout.rotation)[:-1, :-1]
        #size = np.array((self.layout.size[0], self.layout.size[1], 0))
        size = self.layout.measure
        for i in range(0, self.vertices.size, 5):
            b = self.vertices[i:i+3]
            self.vertices[i:i+3] = np.matmul(rotation_matrix, (size * b)) + self.layout.position

    def drop(self):
        world.renderers.pics.remove_pic(self)
        self.layout.drop()
        glDeleteTextures([self.texture_id])
