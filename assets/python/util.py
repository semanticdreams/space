import os
import time
import sys
import importlib
import contextlib
import contextvars
import operator
import json
import random
import hashlib
import colorsys
from datetime import datetime
from collections import defaultdict
import OpenGL
from OpenGL.GL import *
from OpenGL.GL.shaders import *
import OpenGL.GLU as glu
import numpy, math
from PIL import Image

import colors


nested_defaultdict = lambda: defaultdict(nested_defaultdict)


def one(items):
    assert len(items) == 1, len(items)
    return items[0]


def one_or_none(items):
    if len(items) == 1:
        return items[0]
    assert not items, len(items)
    return None


def read_file(filename):
    with open(filename) as f:
        return f.read()


def arrays2elements(vertices):
    # Step 1: Identify unique vertices
    unique_vertices, index_map = np.unique(vertices, axis=0, return_inverse=True)

    # Step 2: Create index buffer
    indices = np.arange(len(vertices))
    optimized_indices = index_map[indices]

    # Step 3: Update vertex data to reference unique indices
    optimized_vertices = unique_vertices[optimized_indices]

    return optimized_vertices, optimized_indices


@contextlib.contextmanager
def scoped_contextvar(contextvar, value):
    token = contextvar.set(value)
    try:
        yield
    finally:
        contextvar.reset(token)


def mapattr(items, *attr_names):
    getter = operator.attrgetter(*attr_names)
    return [getter(x) for x in items]


def truncate_string_with_ellipsis(s, max_length):
    if len(s) > max_length:
        return s[:max_length - 3].strip() + "..."
    return s


def angle_between_vectors(v1, v2):
    v1 = np.array(v1)
    v2 = np.array(v2)

    dot_product = np.dot(v1, v2)
    norm_product = np.linalg.norm(v1) * np.linalg.norm(v2)

    # Clamp value to avoid domain errors due to floating point precision
    cos_angle = np.clip(dot_product / norm_product, -1.0, 1.0)
    angle_rad = np.arccos(cos_angle)

    return angle_rad  # in radians


def wrap_text(text, width=80, max_lines=None):
    wrapped_text = []
    # Split the text into lines based on existing newlines, preserving empty lines
    lines = text.split('\n')
    for line in lines:
        if line == '':  # Check for an empty line which represents a newline
            wrapped_text.append(line)
            continue
        current_line = ''
        for char in line:
            current_line += char
            if len(current_line) == width:
                wrapped_text.append(current_line)
                current_line = ''
        # Append any remaining text in current_line that didn't reach the width limit
        if current_line:
            wrapped_text.append(current_line)
    # Handle case where text ends with newlines
    if text.endswith('\n'):
        wrapped_text.append('')
    if max_lines:
        #wrapped_text = wrapped_text[-max_lines:]
        wrapped_text = wrapped_text[:max_lines]
    return '\n'.join(wrapped_text)


def wrap_text2(text, width=80, max_lines=None, break_words=True):
    import textwrap

    wrapped_text = []
    lines = text.split('\n')  # Split into existing lines (preserving empty ones)

    for line in lines:
        if line.strip() == '':
            wrapped_text.append('')  # Preserve empty lines
            continue
        if break_words:
            # Manual character-based wrap
            current_line = ''
            for char in line:
                current_line += char
                if len(current_line) == width:
                    wrapped_text.append(current_line)
                    current_line = ''
            if current_line:
                wrapped_text.append(current_line)
        else:
            # Use textwrap for word-based wrapping
            wrapped_lines = textwrap.wrap(line, width=width, break_long_words=False, replace_whitespace=False)
            wrapped_text.extend(wrapped_lines)

    if text.endswith('\n'):
        wrapped_text.append('')

    if max_lines:
        wrapped_text = wrapped_text[:max_lines]

    return '\n'.join(wrapped_text)


def time_ago(timestamp):
    now = time.time()
    diff = now - timestamp

    if diff < 60:
        return f"{int(diff)} sec ago"
    elif diff < 3600:
        minutes = int(diff / 60)
        return f"{minutes} min ago"
    elif diff < 86400:
        hours = int(diff / 3600)
        return f"{hours} h ago"
    else:
        days = int(diff / 86400)
        return f"{days} d ago"


def multi_intersect(ray, objs, include_obj=False):
    if not objs:
        return (False, None, None, None) if include_obj else (False, None, None)
    min_f, min_i, min_d, min_o = (*objs[0].intersect(ray), objs[0])
    for obj in objs[1:]:
        f, i, d = obj.intersect(ray)
        if f and (not min_f or d < min_d):
            min_f, min_i, min_d, min_o = f, i, d, obj
    return (min_f, min_i, min_d, min_o) if include_obj else (min_f, min_i, min_d)


def fuzzy_match(str1, str2):
    if len(str1) > len(str2):
        short_str, long_str = str2, str1
    else:
        short_str, long_str = str1, str2
    short_str = short_str.lower()
    long_str = long_str.lower()
    long_index = 0
    for short_char in short_str:
        long_index = long_str.find(short_char, long_index)
        if long_index == -1:
            return False
        long_index += 1
    return True


def normalize(v):
    norm = np.linalg.norm(v, ord=1)
    if norm == 0:
        norm = np.finfo(v.dtype).eps
    return v / norm


def unproject(v, view, projection, viewport):
    v = (v[0], viewport[3] - v[1], v[2])
    return np.array(glu.gluUnProject(
        *v,
        view.astype('d'),
        projection.astype('d'),
        viewport)
    )


def ray_from_screen_pos(pos, view=None, projection=None, viewport=None):
    view = world.camera.camera.get_view_matrix() if view is None else view
    projection = world.projection.value if projection is None else projection
    viewport = world.viewport.value if viewport is None else viewport
    a = unproject((pos[0], pos[1], 0.0), view, projection, viewport)
    b = unproject((pos[0], pos[1], 1.0), view, projection, viewport)
    return z.Ray(a, normalize(b - a))


def load_texture(filename):
    """load OpenGL 2D texture from given image file"""
    img = Image.open(filename)
    imgData = numpy.array(list(img.getdata()), np.int8)
    texture = glGenTextures(1)
    glPixelStorei(GL_UNPACK_ALIGNMENT,1)
    glBindTexture(GL_TEXTURE_2D, texture)
    glPixelStorei(GL_UNPACK_ALIGNMENT,1)
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img.size[0], img.size[1],
                 0, GL_RGBA, GL_UNSIGNED_BYTE, imgData)
    glBindTexture(GL_TEXTURE_2D, 0)
    return texture

def perspective(fov, aspect, zNear, zFar):
    """returns matrix equivalent for gluPerspective"""
    fovR = math.radians(45.0)
    f = 1.0/math.tan(fovR/2.0)
    return numpy.array([f/float(aspect), 0.0,   0.0,                0.0,
                        0.0,        f,   0.0,                0.0,
                        0.0, 0.0, (zFar+zNear)/float(zNear-zFar),  -1.0,
                        0.0, 0.0, 2.0*zFar*zNear/float(zNear-zFar), 0.0],
                       numpy.float32)

def ortho(l, r, b, t, n, f):
    """returns matrix equivalent of glOrtho"""
    return numpy.array([2.0/float(r-l), 0.0, 0.0, 0.0,
                        0.0, 2.0/float(t-b), 0.0, 0.0,
                        0.0, 0.0, -2.0/float(f-n), 0.0,
                        -(r+l)/float(r-l), -(t+b)/float(t-b),
                        -(f+n)/float(f-n), 1.0],
                       numpy.float32)


def lookAt(eye, center, up):
    """returns matrix equivalent of gluLookAt - based on MESA implementation"""
    # create an identity matrix
    m = np.identity(4, float)

    forward = np.array(center) - np.array(eye)
    norm = np.linalg.norm(forward)
    forward /= norm

    # normalize up vector
    norm = np.linalg.norm(up)
    up /= norm

    # Side = forward x up
    side = np.cross(forward, up)
    # Recompute up as: up = side x forward
    up = np.cross(side, forward)

    m[0][0] = side[0]
    m[1][0] = side[1]
    m[2][0] = side[2]

    m[0][1] = up[0]
    m[1][1] = up[1]
    m[2][1] = up[2]

    m[0][2] = -forward[0]
    m[1][2] = -forward[1]
    m[2][2] = -forward[2]

    # eye translation
    t = np.identity(4, float)
    t[3][0] += -eye[0]
    t[3][1] += -eye[1]
    t[3][2] += -eye[2]

    return t.dot(m)


class JSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return {"date": obj.isoformat()}
        return json.JSONEncoder.default(self, obj)


def parse_json_obj(obj):
    for key, value in obj.items():
        if isinstance(value, dict) and 'date' in value:
            try:
                obj[key] = datetime.fromisoformat(value['date'])
            except ValueError:
                pass
    return obj


def hash_string_to_01(input_string):
    input_bytes = input_string.encode('utf-8')
    hash_object = hashlib.sha256(input_bytes)
    hash_bytes = hash_object.digest()
    hash_int = int.from_bytes(hash_bytes, byteorder='big')
    return hash_int / 2**256


def random_color(alpha=1):
    return np.array((
        random.random(), random.random(), random.random(),
        alpha
    ), float)


def hash_color(s, saturation=1, brightness=1, alpha=1, seed=0):
    s = s + str(seed)
    m = hashlib.sha256()
    m.update(s.encode("utf-8"))
    int_hash = int.from_bytes(m.digest(), "big")

    # normalize to float between 0 and 1
    float_hash = int_hash / (2**256 - 1)

    hue = float_hash
    r, g, b = colorsys.hsv_to_rgb(hue, saturation, brightness)
    rgba_color = (r, g, b, alpha)

    return rgba_color


def create_linear_color_swatch(color):
    r, g, b, _ = color

    strengths = [0.05 * i for i in range(1, 20)]
    swatch = dict()

    for strength in strengths:
        ds = 0.5 - strength
        new_color = (
            max(0, min(1, r + ds)),
            max(0, min(1, g + ds)),
            max(0, min(1, b + ds)),
            1
        )
        swatch[round(strength * 1000)] = new_color

    return swatch


def create_color_swatch(color):
    return colors.create_color_swatch(color[:3])


def adjust_color_brightness(rgba_color, delta_value):
    # Convert the NumPy array to a Python tuple and separate the alpha value
    rgb = tuple(rgba_color[:3])
    alpha = rgba_color[3]

    # Convert RGB color to HSV
    h, s, v = colorsys.rgb_to_hsv(*rgb)

    # Adjust the value (brightness)
    v = np.clip(v + delta_value, 0, 1)  # Ensure v stays within [0, 1]

    # Convert back to RGB
    new_rgb = np.array(colorsys.hsv_to_rgb(h, s, v))

    # Append the original alpha value and return
    return np.append(new_rgb, alpha)


def adjust_perceptual_color_brightness(rgba_color, delta_value):
    import colorspacious as cs
    # Convert the NumPy array to a Python tuple and separate the alpha value
    rgb = tuple(rgba_color[:3])
    alpha = rgba_color[3]

    # Convert RGB to CIECAM02
    cam = cs.cspace_convert(rgb, 'sRGB1', 'JCh')
    j, c, h = cam

    # Adjust the J (lightness) component
    j = np.clip(j + (delta_value * 100), 0, 100)  # J is in range [0, 100] in CIECAM02

    # Convert CIECAM02 back to RGB
    new_rgb = np.array(cs.cspace_convert((j, c, h), 'JCh', 'sRGB1'))

    # Append the original alpha value and return
    return np.append(new_rgb, alpha)


def get_luminance(color):
    return 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2]


import shutil
import re
from pathlib import Path
def backup_file(file_path):
    """
    Create a backup copy of the given file, appending .bak<i> to the filename,
    where <i> is one greater than the highest existing backup index for that file.
    The first backup will use .bak1.

    :param file_path: Path to the original file.
    :return: Path object pointing to the new backup file.
    :raises FileNotFoundError: If the original file does not exist.
    """
    original = Path(file_path)
    if not original.is_file():
        raise FileNotFoundError(f"No such file: '{file_path}'")

    parent = original.parent
    base = original.name

    # Pattern to match existing backups: <filename>.bak<digits>
    pattern = re.compile(rf"^{re.escape(base)}\.bak(\d+)$")
    max_index = 0

    # Scan parent directory for matching backups
    for entry in parent.iterdir():
        if not entry.is_file():
            continue
        match = pattern.match(entry.name)
        if match:
            idx = int(match.group(1))
            if idx > max_index:
                max_index = idx

    new_index = max_index + 1
    backup_name = f"{base}.bak{new_index}"
    backup_path = parent / backup_name

    # Perform the copy preserving metadata
    shutil.copy2(original, backup_path)
    return backup_path


def backup_db():
    backup_file(world.db_path)


import inspect
def has_mandatory_params(func):
    sig = inspect.signature(func)
    params = list(sig.parameters.values())[1:]
    mandatory = [
        p for p in params
        if p.default == inspect.Parameter.empty
        and p.kind not in (inspect.Parameter.VAR_POSITIONAL, inspect.Parameter.VAR_KEYWORD)
    ]
    return len(mandatory) > 0


class Signal:
    def __init__(self):
        self.callbacks = []

    def emit(self, *args, **kwargs):
        for callback in list(self.callbacks):
            callback(*args, **kwargs)

    def connect(self, callback):
        self.callbacks.append(callback)

    def disconnect(self, callback, not_connected_ok=False):
        if callback not in self.callbacks:
            if not_connected_ok:
                return
            raise ValueError('Callback not connected')
        self.callbacks.remove(callback)

    def clear_callbacks(self):
        self.callbacks = []
