import sdl2
import sdl2.ext
import numpy as np
from OpenGL.GL import *
from OpenGL.GL.shaders import compileProgram, compileShader
import glm
import ctypes
import time


VERTEX_SHADER = """
#version 330 core
layout(location = 0) in vec3 position;
layout(location = 1) in mat4 model;

uniform mat4 view;
uniform mat4 projection;

out vec3 fragWorldPos;
flat out int instanceID;

void main() {
    vec4 worldPos = model * vec4(position, 1.0);
    fragWorldPos = worldPos.xyz;
    instanceID = gl_InstanceID;
    gl_Position = projection * view * worldPos;
}
"""

FRAGMENT_SHADER = """
#version 330 core
in vec3 fragWorldPos;
flat in int instanceID;

uniform mat4 inverseClipTransforms[100];

out vec4 FragColor;

void main() {
    vec3 localPos = (inverseClipTransforms[instanceID] * vec4(fragWorldPos, 1.0)).xyz;

    if (abs(localPos.x) > 0.5 || abs(localPos.y) > 0.5 || abs(localPos.z) > 0.5) {
        discard;
    }

    FragColor = vec4(0.2 + 0.6 * float(instanceID % 2), 0.6, 1.0, 1.0);
}
"""


# ---------- Geometry ----------
quad_vertices = np.array([
    -0.5, -0.5, 0.0,
     0.5, -0.5, 0.0,
     0.5,  0.5, 0.0,
    -0.5,  0.5, 0.0
], dtype=np.float32)

quad_indices = np.array([0, 1, 2, 2, 3, 0], dtype=np.uint32)


class Scroll:
    def __init__(self):
        self.shader = compileProgram(
            compileShader(VERTEX_SHADER, GL_VERTEX_SHADER),
            compileShader(FRAGMENT_SHADER, GL_FRAGMENT_SHADER)
        )
        self.vao = glGenVertexArrays(1)
        self.vbo = glGenBuffers(1)
        self.ebo = glGenBuffers(1)
        self.instanceVBO = glGenBuffers(1)

        glBindVertexArray(self.vao)

        glBindBuffer(GL_ARRAY_BUFFER, self.vbo)
        glBufferData(GL_ARRAY_BUFFER, quad_vertices.nbytes, quad_vertices, GL_STATIC_DRAW)

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, self.ebo)
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, quad_indices.nbytes, quad_indices, GL_STATIC_DRAW)

        # Position attribute
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 0, ctypes.c_void_p(0))

        # Instance Model Matrices
        glBindBuffer(GL_ARRAY_BUFFER, self.instanceVBO)
        glBufferData(GL_ARRAY_BUFFER, 100 * 64, None, GL_DYNAMIC_DRAW)

        for i in range(4):
            glEnableVertexAttribArray(1 + i)
            glVertexAttribPointer(1 + i, 4, GL_FLOAT, GL_FALSE, 64, ctypes.c_void_p(i * 16))
            glVertexAttribDivisor(1 + i, 1)

        glBindVertexArray(0)

        # ---------- Uniforms ----------
        glUseProgram(self.shader)
        self.viewLoc = glGetUniformLocation(self.shader, "view")
        self.projLoc = glGetUniformLocation(self.shader, "projection")
        self.inverseClipLoc = glGetUniformLocation(self.shader, "inverseClipTransforms")

        # ---------- Main Loop ----------
        self.NUM_INSTANCES = 10
        self.running = True
        self.start_time = time.time()

    def update(self):
        glUseProgram(self.shader)

        width, height = 800, 600
        view = glm.lookAt(glm.vec3(0, 0, 5), glm.vec3(0, 0, 0), glm.vec3(0, 1, 0))
        proj = glm.perspective(glm.radians(45.0), width / height, 0.1, 100.0)

        glUniformMatrix4fv(self.viewLoc, 1, GL_FALSE, glm.value_ptr(view))
        glUniformMatrix4fv(self.projLoc, 1, GL_FALSE, glm.value_ptr(proj))

        model_matrices = []
        inverse_clip_matrices = []
        current_time = time.time() - self.start_time

        for i in range(self.NUM_INSTANCES):
            angle = current_time + i
            pos = glm.vec3((i % 5) - 2.0, (i // 5) - 0.5, 0)
            model = glm.translate(glm.mat4(1.0), pos)
            model = glm.rotate(model, angle, glm.vec3(0, 0, 1))
            model_matrices.append(model)
            inverse_clip_matrices.append(glm.inverse(model))

        model_data = np.array([np.array(m.to_list(), dtype=np.float32) for m in model_matrices])
        glBindBuffer(GL_ARRAY_BUFFER, self.instanceVBO)
        glBufferSubData(GL_ARRAY_BUFFER, 0, model_data.nbytes, model_data)

        flat_inverse = np.array([m.to_list() for m in inverse_clp_matrices], dtype=np.float32).reshape(-1)
        glUniformMatrix4fv(self.inverseClipLoc, self.NUM_INSTANCES, GL_FALSE, flat_inverse)

        glBindVertexArray(self.vao)
        glDrawElementsInstanced(GL_TRIANGLES, 6, GL_UNSIGNED_INT, None, self.NUM_INSTANCES)
        glBindVertexArray(0)

    def drop(self):
        glDeleteVertexArrays(1, [self.vao])
        glDeleteBffers(1, [self.vbo, self.ebo, self.instanceVBO])
        glDeleteProgram(self.shader)