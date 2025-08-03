from OpenGL.GL import *


class Renderers:
    def __init__(self):
        self.sub_worlds = []

        self.text_renderer = z.TextRenderer()
        self.scene_text_vectors = {}
        self.hud_text_vectors = {}

        self.triangle_renderer = z.TriangleRenderer()
        self.scene_triangle_vector = z.Vector()
        self.hud_triangle_vector = z.Vector()

        self.line_renderer = z.LineRenderer()
        self.line_vector = z.Vector()

        self.line_strips = []

        self.skybox_renderer = z.SkyboxRenderer()

        self.pics = z.Pics()
        self.points = z.Points()
        self.meshes = z.Meshes()

        self.lua_world = z.LuaWorld()

        self.fxaa = z.Fxaa()

        self.create_final_fbo()

        world.renderers = self

    def viewport_changed(self, viewport):
        glDeleteFramebuffers(1, self.final_fbo)
        glDeleteRenderbuffers(1, self.final_rbo)
        self.create_final_fbo()
        self.lua_world.viewport_changed(viewport)

    def create_final_fbo(self):
        width, height = world.viewport.value[2:4]
        self.final_fbo = glGenFramebuffers(1)
        glBindFramebuffer(GL_FRAMEBUFFER, self.final_fbo)
        self.final_rbo = glGenRenderbuffers(1)
        glBindRenderbuffer(GL_RENDERBUFFER, self.final_rbo)
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, width, height)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, self.final_rbo)
        assert glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE
        glBindFramebuffer(GL_FRAMEBUFFER, 0)

    def get_hud_text_vector(self, font):
        if font not in self.hud_text_vectors:
            self.hud_text_vectors[font] = z.Vector()
        return self.hud_text_vectors[font]

    def get_scene_text_vector(self, font):
        if font not in self.scene_text_vectors:
            self.scene_text_vectors[font] = z.Vector()
        return self.scene_text_vectors[font]

    def render(self):
        for sub_world in self.sub_worlds:
            sub_world.prerender()

        glBindFramebuffer(GL_FRAMEBUFFER, self.fxaa.fbo)
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LESS)
        glClearColor(*world.window.clear_color)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        view = world.camera.camera.get_view_matrix()

        self.skybox_renderer.render()

        self.triangle_renderer.render(world.camera['default'].get_view_matrix(),
                                      world.projection.value,
                                      self.scene_triangle_vector.array,
                                      world.camera['default'].position)
        #world.scroll.update()

        self.pics.render(view, world.projection.value)

        self.line_renderer.render_lines(view,
                                        world.projection.value, self.line_vector.array)
        self.line_renderer.render_line_strips(view,
                                              world.projection.value,
                                              [x.vector.array for x in self.line_strips])

        self.points.render(view, world.projection.value)
        self.meshes.render(view, world.projection.value)

        for sub_world in self.sub_worlds:
            sub_world.render(view, world.projection.value)

        self.lua_world.render(view, world.projection.value)

        glBindFramebuffer(GL_FRAMEBUFFER, self.final_fbo)
        glDisable(GL_DEPTH_TEST)
        glClear(GL_COLOR_BUFFER_BIT)
        self.fxaa.render()

        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, self.fxaa.rbo)
        glEnable(GL_DEPTH_TEST)

        for font, vector in self.scene_text_vectors.items():
            self.text_renderer.render(world.camera['default'].get_view_matrix(),
                                      world.projection.value,
                                      vector.array, font)

        self.triangle_renderer.render(world.camera['identity'].get_view_matrix(),
                                      world.hud_projection.value,
                                      self.hud_triangle_vector.array,
                                      world.camera['identity'].position)

        for font, vector in self.hud_text_vectors.items():
            self.text_renderer.render(world.camera['identity'].get_view_matrix(),
                                      world.hud_projection.value,
                                      vector.array, font)

        glBindFramebuffer(GL_READ_FRAMEBUFFER, self.final_fbo)
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)
        glBlitFramebuffer(0, 0, world.viewport.value[2], world.viewport.value[3],
                          0, 0, world.viewport.value[2], world.viewport.value[3],
                          GL_COLOR_BUFFER_BIT, GL_NEAREST)

    def drop(self):
        pass
