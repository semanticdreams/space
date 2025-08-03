import ctypes
import json
import time
import os
import numpy as np

import sdl2
import sdl2.ext
from sdl2 import video

from OpenGL.GL import *
import OpenGL.GLU as glu


class Window:
    def __init__(self):
        self.mouse_pos = (0, 0)
        self.keys = set()

        self.mouse_button = z.Signal()
        self.mouse_motion = z.Signal()
        self.scrolled = z.Signal()
        self.keyboard = z.Signal()
        self.keydown = z.Signal()
        self.character = z.Signal()

        #glEnable(GL_DEPTH_TEST)
        #glDepthFunc(GL_LESS)

        #glEnable(GL_BLEND)
        #glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        #glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)

        self.set_clear_color(json.loads(world.settings.get_value('window/clear_color') or '[0.1, 0.1, 0.2, 1.0]'))

    def set_clear_color(self, color):
        self.clear_color = color
        glClearColor(*color)
        print("python set clear color", color)

    def clear(self):
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

    def get_viewport(self):
        return np.array(glGetIntegerv(GL_VIEWPORT), 'i')

    def get_clear_color(self):
        return np.array(glGetFloatv(GL_COLOR_CLEAR_VALUE), 'f')

    def update_clear_color(self, color):
        self.set_clear_color(color)
        world.settings.set_value('window/clear_color', json.dumps(color))

    def on_text_input(self, text):
        codepoint = ord(text)
        self.character.emit(codepoint)

    #def handle_event(self, event):
    #    if event.type == sdl2.SDL_CONTROLLERBUTTONDOWN:
    #        world.gamepads[event.cbutton.which].button_down.emit(
    #            event.cbutton.button, event.cbutton.state, event.cbutton.timestamp)
    #    elif event.type == sdl2.SDL_CONTROLLERBUTTONUP:
    #        world.gamepads[event.cbutton.which].button_up.emit(
    #            event.cbutton.button, event.cbutton.state, event.cbutton.timestamp)
    #    elif event.type == sdl2.SDL_CONTROLLERAXISMOTION:
    #        world.gamepads[event.caxis.which].motion.emit(
    #            event.caxis.axis, event.caxis.value, event.caxis.timestamp)
    #    elif event.type == sdl2.SDL_CONTROLLERDEVICEADDED:
    #        world.gamepads.add(event.cdevice.which)
    #    elif event.type == sdl2.SDL_CONTROLLERDEVICEREMOVED:
    #        world.gamepads.remove(event.cdevice.which)
