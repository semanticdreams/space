from OpenGL.GL import *
from OpenGL.GL.shaders import compileProgram, compileShader


class SubWorld:
    vertex_shader_source = """
    #version 330 core
    layout(location = 0) in vec3 position;
    layout(location = 1) in vec2 texCoords;

    uniform mat4 projection;
    uniform mat4 view;

    out vec2 TexCoords;

    void main()
    {
        TexCoords = texCoords;
        gl_Position = projection * view * vec4(position, 1.0);
    }
    """

    fragment_shader_source = """
    #version 330 core
    out vec4 FragColor;
    in vec2 TexCoords;

    uniform sampler2D screenTexture;

    void main()
    {
        FragColor = texture(screenTexture, TexCoords);
    }
    """
    def __init__(self, view):
        self.view = view

        self.shader = compileProgram(
            compileShader(self.vertex_shader_source, GL_VERTEX_SHADER),
            compileShader(self.fragment_shader_source, GL_FRAGMENT_SHADER)
        )

        self.width, self.height = 300, 200

        self.fbo, self.screen_texture = self.create_framebuffer(self.width, self.height)

        self.update_quad()

        self.camera = z.Camera([0, 0, 0], [1, 0, 0, 0])
        self.projection = z.Projection()
        self.projection.viewport_changed([0, 0, self.width, self.height])

        self.text_renderer = z.TextRenderer()
        self.text_vector = z.Vector()

        self.triangle_renderer = z.TriangleRenderer()
        self.triangle_vector = z.Vector()

    def update_quad(self):
        self.quad_vao = self.create_quad()

    def prerender(self):
        glBindFramebuffer(GL_FRAMEBUFFER, self.fbo)
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LESS)
        glClearColor(1.0, 0.0, 0.0, 1.0)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        self.triangle_renderer.render(
            self.camera.get_view_matrix(),
            self.projection.value,
            self.triangle_vector.array,
            self.camera.position
        )
        self.text_renderer.render(
            self.camera.get_view_matrix(),
            self.projection.value,
            self.text_vector.array,
            world.themes.theme.font
        )

        glBindFramebuffer(GL_FRAMEBUFFER, 0)

    def render(self, view, projection):
        glUseProgram(self.shader)
        glBindVertexArray(self.quad_vao)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, self.screen_texture)
        glUniform1i(glGetUniformLocation(self.shader, b"screenTexture"), 0)
        glUniform2f(glGetUniformLocation(self.shader, b"resolution"), float(self.width), float(self.height))
        glUniformMatrix4fv(
            glGetUniformLocation(self.shader, b'projection'), 1, GL_FALSE, projection)
        glUniformMatrix4fv(
            glGetUniformLocation(self.shader, b'view'), 1, GL_FALSE, view)
        glDrawArrays(GL_TRIANGLES, 0, 6)

    def drop(self):
        glDeleteFramebuffers(1, self.fbo)
        glDeleteTextures(self.screen_texture)
        glDeleteVertexArrays(self.quad_vao)
        glDeleteProgram(self.shader)

    def create_framebuffer(self, width, height):
        # Create Framebuffer
        fbo = glGenFramebuffers(1)
        glBindFramebuffer(GL_FRAMEBUFFER, fbo)

        # Create Texture Attachment
        tex = glGenTextures(1)
        glBindTexture(GL_TEXTURE_2D, tex)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, None)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

        # Attach Texture to Framebuffer
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0)

        # Create Renderbuffer Object for Depth & Stencil
        rbo = glGenRenderbuffers(1)
        glBindRenderbuffer(GL_RENDERBUFFER, rbo)
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, rbo)

        if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFER_COMPLETE:
            print("Framebuffer is not complete!")

        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        return fbo, tex

    def create_quad(self):
        layout = self.view.layout

        quad_vertices = v = np.array([
            # positions   # texCoords
            0.0,  1.0, 0,  0.0, 1.0,
            0.0, 0.0, 0,  0.0, 0.0,
            1.0, 0.0, 0,  1.0, 0.0,
            0.0,  1.0,0,   0.0, 1.0,
            1.0, 0.0,  0, 1.0, 0.0,
            1.0,  1.0, 0,  1.0, 1.0
        ], dtype=np.float32)
        rotation_matrix = transformations.quaternion_matrix(
            layout.rotation)[:-1, :-1]
        size = np.array((layout.size[0], layout.size[1], 0))
        for i in range(0, v.size, 5):
            b = quad_vertices[i:i+3]
            v[i:i+3] = np.matmul(rotation_matrix, (size * b)) \
                    + layout.position

        vao = glGenVertexArrays(1)
        vbo = glGenBuffers(1)
        glBindVertexArray(vao)
        glBindBuffer(GL_ARRAY_BUFFER, vbo)
        glBufferData(GL_ARRAY_BUFFER, quad_vertices.nbytes, quad_vertices, GL_STREAM_DRAW)
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * quad_vertices.itemsize, ctypes.c_void_p(0))
        glEnableVertexAttribArray(1)
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * quad_vertices.itemsize, ctypes.c_void_p(12))
        glBindBuffer(GL_ARRAY_BUFFER, 0)
        glBindVertexArray(0)
        return vao
