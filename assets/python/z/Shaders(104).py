import pypika
from OpenGL.GL import *
from OpenGL.GL.shaders import *
import OpenGL.GLU as glu


class Shaders:
    def __init__(self):
        self.reload()
        world.shaders = self

    def reload(self):
        self.entities = z.ShaderEntity.all()

    def create_shader(self):
        z.ShaderEntity.create()
        self.reload()

    def find_shader(self, name):
        return one([x for x in self.entities if x.name == name])

    def build_program(self, vertex_shader_code, fragment_shader_code):
        vertex_shader = compileShader([vertex_shader_code.code_str], GL_VERTEX_SHADER)
        fragment_shader = compileShader([fragment_shader_code.code_str], GL_FRAGMENT_SHADER)
        program = glCreateProgram()
        if not program:
            raise RuntimeError('glCreateProgram faled!')
        glAttachShader(program, vertex_shader)
        glAttachShader(program, fragment_shader)
        glLinkProgram(program)
        linked = glGetProgramiv(program, GL_LINK_STATUS)
        if not linked:
            infoLen = glGetProgramiv(program, GL_INFO_LOG_LENGTH)
            infoLog = ""
            if infoLen > 1:
                infoLog = glGetProgramInfoLog(program, infoLen, None);
            glDeleteProgram(program)
            raise RunTimeError("Error linking program:\n%s\n", infoLog);
        return program

    def drop(self):
        pass
