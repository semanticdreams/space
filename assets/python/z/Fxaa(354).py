from OpenGL.GL import *
from OpenGL.GL.shaders import compileProgram, compileShader

vertex_shader_source = """
#version 330 core
out vec2 v_texCoord;

void main(void)
{
	vec4 vertices[4] = vec4[4](vec4(-1.0, -1.0, 0.0, 1.0), vec4(1.0, -1.0, 0.0, 1.0), vec4(-1.0, 1.0, 0.0, 1.0), vec4(1.0, 1.0, 0.0, 1.0));
	vec2 texCoord[4] = vec2[4](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0));

	v_texCoord = texCoord[gl_VertexID];

	gl_Position = vertices[gl_VertexID];
}
"""

fragment_shader_source = """
#version 330 core
out vec4 fragColor;
in vec2 v_texCoord;

uniform sampler2D u_colorTexture;

uniform vec2 u_texelStep;
uniform int u_showEdges;
uniform int u_fxaaOn;

uniform float u_lumaThreshold;
uniform float u_mulReduce;
uniform float u_minReduce;
uniform float u_maxSpan;

// see FXAA
// http://developer.download.nvidia.com/assets/gamedev/files/sdk/11/FXAA_WhitePaper.pdf
// http://iryoku.com/aacourse/downloads/09-FXAA-3.11-in-15-Slides.pdf
// http://horde3d.org/wiki/index.php5?title=Shading_Technique_-_FXAA

void main(void)
{
    vec3 rgbM = texture(u_colorTexture, v_texCoord).rgb;

	// Possibility to toggle FXAA on and off.
	if (u_fxaaOn == 0)
	{
		fragColor = vec4(rgbM, 1.0);

		return;
	}

	// Sampling neighbour texels. Offsets are adapted to OpenGL texture coordinates.
	vec3 rgbNW = textureOffset(u_colorTexture, v_texCoord, ivec2(-1, 1)).rgb;
    vec3 rgbNE = textureOffset(u_colorTexture, v_texCoord, ivec2(1, 1)).rgb;
    vec3 rgbSW = textureOffset(u_colorTexture, v_texCoord, ivec2(-1, -1)).rgb;
    vec3 rgbSE = textureOffset(u_colorTexture, v_texCoord, ivec2(1, -1)).rgb;

	// see http://en.wikipedia.org/wiki/Grayscale
	const vec3 toLuma = vec3(0.299, 0.587, 0.114);

	// Convert from RGB to luma.
	float lumaNW = dot(rgbNW, toLuma);
	float lumaNE = dot(rgbNE, toLuma);
	float lumaSW = dot(rgbSW, toLuma);
	float lumaSE = dot(rgbSE, toLuma);
	float lumaM = dot(rgbM, toLuma);

	// Gather minimum and maximum luma.
	float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
	float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

	// If contrast is lower than a maximum threshold ...
	if (lumaMax - lumaMin <= lumaMax * u_lumaThreshold)
	{
		// ... do no AA and return.
		fragColor = vec4(rgbM, 1.0);

		return;
	}

	// Sampling is done along the gradient.
	vec2 samplingDirection;
	samplingDirection.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    samplingDirection.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    // Sampling step distance depends on the luma: The brighter the sampled texels, the smaller the final sampling step direction.
    // This results, that brighter areas are less blurred/more sharper than dark areas.
    float samplingDirectionReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.25 * u_mulReduce, u_minReduce);

	// Factor for norming the sampling direction plus adding the brightness influence.
	float minSamplingDirectionFactor = 1.0 / (min(abs(samplingDirection.x), abs(samplingDirection.y)) + samplingDirectionReduce);

    // Calculate final sampling direction vector by reducing, clamping to a range and finally adapting to the texture size.
    samplingDirection = clamp(samplingDirection * minSamplingDirectionFactor, vec2(-u_maxSpan), vec2(u_maxSpan)) * u_texelStep;

	// Inner samples on the tab.
	vec3 rgbSampleNeg = texture(u_colorTexture, v_texCoord + samplingDirection * (1.0/3.0 - 0.5)).rgb;
	vec3 rgbSamplePos = texture(u_colorTexture, v_texCoord + samplingDirection * (2.0/3.0 - 0.5)).rgb;

	vec3 rgbTwoTab = (rgbSamplePos + rgbSampleNeg) * 0.5;

	// Outer samples on the tab.
	vec3 rgbSampleNegOuter = texture(u_colorTexture, v_texCoord + samplingDirection * (0.0/3.0 - 0.5)).rgb;
	vec3 rgbSamplePosOuter = texture(u_colorTexture, v_texCoord + samplingDirection * (3.0/3.0 - 0.5)).rgb;

	vec3 rgbFourTab = (rgbSamplePosOuter + rgbSampleNegOuter) * 0.25 + rgbTwoTab * 0.5;

	// Calculate luma for checking against the minimum and maximum value.
	float lumaFourTab = dot(rgbFourTab, toLuma);

	// Are outer samples of the tab beyond the edge ...
	if (lumaFourTab < lumaMin || lumaFourTab > lumaMax)
	{
		// ... yes, so use only two samples.
		fragColor = vec4(rgbTwoTab, 1.0);
	}
	else
	{
		// ... no, so use four samples.
		fragColor = vec4(rgbFourTab, 1.0);
	}

	// Show edges for debug purposes.
	if (u_showEdges != 0)
	{
		fragColor.r = 1.0;
	}
}
"""

class Fxaa:
    MAX_MUL_REDUCE_RECIPROCAL = 256.0
    MAX_MIN_REDUCE_RECIPROCAL = 512.0
    MAX_MAX_SPAN = 16.0

    def __init__(self):
        self.on = 1
        self.show_edges = 0
        self.luma_threshold = 0.5 # step +0.05
        self.mul_reduce_reciprocal = 8.0 # step *2.0
        self.min_reduce_reciprocal = 128.0 # step *2.0
        self.max_span = 8.0 # step +1.0

        self.shader = compileProgram(
            compileShader(vertex_shader_source, GL_VERTEX_SHADER),
            compileShader(fragment_shader_source, GL_FRAGMENT_SHADER)
        )

        self.fbo, self.screen_texture = self.create_framebuffer(*world.viewport.value[2:4])

        self.vao = glGenVertexArrays(1)
        vbo = glGenBuffers(1)
        glBindVertexArray(self.vao)
        glBindVertexArray(0)

    def set_luma_threshold(self, value):
        self.luma_threshold = np.clip(value, 0.0, 1.0)

    def set_mul_reduce_reciprocal(self, value):
        self.mul_reduce_reciprocal = np.clip(value, 1.0, self.MAX_MUL_REDUCE_RECIPROCAL)

    def set_min_reduce_reciprocal(self, value):
        self.min_reduce_reciprocal = np.clip(value, 1.0, self.MAX_MIN_REDUCE_RECIPROCAL)

    def set_max_span(self, value):
        self.max_span = np.clip(value, 1.0, self.MAX_MAX_SPAN)

    def viewport_changed(self, viewport):
        glDeleteFramebuffers(1, self.fbo)
        glDeleteRenderbuffers(1, self.rbo)
        glDeleteTextures(self.screen_texture)
        self.fbo, self.screen_texture = self.create_framebuffer(viewport[2], viewport[3])

    def render(self):
        glUseProgram(self.shader)
        glBindVertexArray(self.vao)
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, self.screen_texture)
        glUniform1i(glGetUniformLocation(self.shader, b"u_colorTexture"), 0)

        glUniform2f(glGetUniformLocation(self.shader, b'u_texelStep'),
                    1.0 / float(world.viewport.value[2]), 1.0 / float(world.viewport.value[3]))
        glUniform1i(glGetUniformLocation(self.shader, b'u_showEdges'), self.show_edges)
        glUniform1i(glGetUniformLocation(self.shader, b'u_fxaaOn'), self.on)
        glUniform1f(glGetUniformLocation(self.shader, b'u_lumaThreshold'), self.luma_threshold)
        glUniform1f(glGetUniformLocation(self.shader, b'u_mulReduce'), 1.0 / self.mul_reduce_reciprocal)
        glUniform1f(glGetUniformLocation(self.shader, b'u_minReduce'), 1.0 / self.min_reduce_reciprocal)
        glUniform1f(glGetUniformLocation(self.shader, b'u_maxSpan'), self.max_span)

        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    def drop(self):
        glDeleteFramebuffers(1, self.fbo)
        glDeleteRenderbuffers(1, self.rbo)
        glDeleteTextures(self.screen_texture)
        glDeleteVertexArrays(self.vao)
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
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

        # Attach Texture to Framebuffer
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0)

        # Create Renderbuffer Object for Depth & Stencil
        self.rbo = glGenRenderbuffers(1)
        glBindRenderbuffer(GL_RENDERBUFFER, self.rbo)

        #glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height)
        #glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, self.rbo)

        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT, width, height)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, self.rbo)

        if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
            print("Framebuffer is not complete!")

        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        return fbo, tex
