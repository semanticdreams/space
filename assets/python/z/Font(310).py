import json
import time
from OpenGL.GL import *
from PIL import Image


class Font:
    def __init__(self, png_path, json_path):
        self.meta = json.load(open(json_path))
        self.texture = self.load_texture(png_path)
        self.glyph_map = {x['unicode']: x for x in self.meta['glyphs']}
        self.monospace = True
        self.advance = 0.5

    def load_texture(self, png_path):
        texture = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, texture)

        image = Image.open(png_path)
        #image_data = np.array(list(image.getdata()), np.uint8)
        image_data = np.asarray(image, np.uint8)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, image.width, image.height, 0, GL_RGB, GL_UNSIGNED_BYTE, image_data)

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        #glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

        #max_anisotropy = glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY)
        #glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY, max_anisotropy)

        return texture

    def drop(self):
        glDeleteTextures(self.texture)
