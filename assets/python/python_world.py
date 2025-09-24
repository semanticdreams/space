import builtins
import sqlite3
import uuid
import os
import sys
import json
import time
import math
import pprint
import numpy
import sdl2

from OpenGL.GL import *
from ctypes import sizeof, c_float, c_void_p, c_uint, string_at

import sys
sys.path.append(os.path.join(os.path.dirname(__file__), 'lib'))

import appdirs

import space
import bullet as bt
import audio as al

from dotenv import load_dotenv
load_dotenv()



class YClass:
    def __call__(self, o, register_type='v'):
        world.apps['Store']['registers']['default'] = o
        world.apps['Store']['register_types']['default'] = register_type

    def __getattr__(self, key):
        if key == 'value':
            return world.apps['Store']['registers']['default']
        elif key == 'register_type':
            return world.apps['Store']['register_types']['default']
        return super().__getattr__(key)


class Z:
    def __getattr__(self, key):
        return world.classes[key]


class PythonWorld:
    def __init__(self, resolution, assets_path, physics, audio):
        self.width, self.height = resolution
        self.physics = physics
        self.audio = audio
        self.assets_path = os.path.abspath(assets_path)

        self.physics.setGravity(0, -9.8, 0)

    def init(self):
        t0 = time.time()

        builtins.world = self
        builtins.pp = pprint.pprint
        builtins.math = math
        builtins.np = numpy
        builtins.sdl2 = sdl2
        builtins.bt = bt
        builtins.al = al
        builtins.json = json
        builtins.time = time

        builtins.z = Z()
        builtins.Y = YClass()

        from util import mapattr, one, one_or_none
        builtins.mapattr = mapattr
        builtins.one = one
        builtins.one_or_none = one_or_none

        import util
        builtins.util = util

        builtins.space = space

        import lib.transformations as transformations
        builtins.transformations = transformations

        self.datadir = appdirs.user_data_dir('space')
        os.makedirs(self.datadir, exist_ok=True)

        self.db_path = os.path.join(self.datadir, 'space.db')
        self.db = sqlite3.connect(self.db_path)
        self.db.row_factory = sqlite3.Row

        from setup_db import setup_db
        setup_db(self.db)

        # load seed
        seed_dir = os.path.join(self.assets_path, 'seed')
        with self.db:
            cursor = self.db.cursor()
            for filename in os.listdir(seed_dir):
                path = os.path.join(seed_dir, filename)
                with open(path) as f:
                    data = json.load(f)
                    cursor.execute(
                        'INSERT OR REPLACE INTO entities'
                        ' (id, type, data, created_at, updated_at)'
                        ' VALUES (?, ?, ?, ?, ?)',
                        (data['id'], data['type'], data['data'], data['created_at'],
                         data['updated_at'])
                    )


        self.next_tick_funcs = []

        from kernels import Kernels
        self.kernels = Kernels()

        from classes import Classes
        self.classes = Classes()

        self.settings = z.Settings()

        self.window = z.Window()

        self.error_views = z.ErrorViews()

        self.aio = z.Aio()

        self.updated = z.Signal()

        self.gamepads = z.Gamepads()
        self.viewport = z.Viewport()
        self.viewport.value[2] = self.width
        self.viewport.value[3] = self.height

        self.projection = z.Projection(self.viewport.value)
        self.hud_projection = z.HudProjection(self.viewport.value)

        self.apps = z.Apps()
        self.apps.run_autostart_apps()

        builtins.G = self.apps['Entities'].get_entity('18')

        self.states.transit(state_name='vim')

        t1 = round(time.time() - t0, 2)
        print(f'initialized in {t1} seconds')

        #self.audio.load_sound("test", os.path.join(self.assets_path, "sounds/test.wav"))
        #self.audio.play_sound("test", (0, 0, 0), True)

        self.apps['Hud'].snackbar_host.show_message(f'Init in {t1}s')

    def viewport_changed(self, viewport):
        self.width, self.height = viewport[2:4]
        self.viewport.viewport_changed(viewport)
        self.projection.viewport_changed(viewport)
        self.hud_projection.viewport_changed(viewport)
        self.renderers.viewport_changed(viewport)
        self.renderers.fxaa.viewport_changed(viewport)

    def next_tick(self, f):
        self.next_tick_funcs.append(f)

    def update(self, delta):
        try:
            for f in self.next_tick_funcs:
                f()
            self.next_tick_funcs.clear()

            self.updated.emit(delta)

            self.floaties.update()
            self.apps['Menus'].update()

            self.renderers.render()

            self.aio.update()

        except Exception as e:
            #raise
            import traceback; print(traceback.format_exc())
            self.report_error(e)

    def report_error(self, e):
        self.apps['ErrorViews'].add(e)

    def unproject(self, position):
        from util import unproject
        return unproject(position, self.camera.camera.get_view_matrix(),
                         self.projection.value, self.viewport.value)

    def screen_pos_ray(self, pos, projection=None, camera=None):
        from util import ray_from_screen_pos
        projection = projection or self.projection
        camera = camera or self.camera['default']
        return ray_from_screen_pos(pos, camera.get_view_matrix(), projection.value,
                                   self.viewport.value)

    def drop(self):
        if self.gamepads.primary:
            self.gamepads.primary.set_led_color((0.01,) * 3)
        self.kernels.drop()
        self.apps.drop()
        self.gamepads.drop()
