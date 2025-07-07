import warnings
import sdl2.ext
import subprocess
import glob
import ctypes
from collections import defaultdict

# TODO https://github.com/alanrme/ds4led/tree/master

class Gamepad:
    def __init__(self, joystick_device_index):
        self.controller = sdl2.SDL_GameControllerOpen(joystick_device_index)
        self.joystick = sdl2.SDL_GameControllerGetJoystick(self.controller)
        self.sdl_id = sdl2.SDL_JoystickInstanceID(self.joystick)
        self.name = sdl2.SDL_GameControllerName(self.controller).decode('utf-8')
        self.serial = None#sdl2.SDL_GameControllerGetSerial(self.controller)
        self.mac_address = None
        if self.serial is not None:
            self.serial = self.serial.decode()
            self.mac_address = self.serial.replace('-', ':')

        # https://github.com/wogscpar/upower-python/blob/master/upower_python/upower.py TODO

        self.pressed = defaultdict(int)

        self.button_down = z.Signal()
        self.button_up = z.Signal()
        self.motion = z.Signal()

    def dump(self):
        return dict(sdl_id=self.sdl_id, name=self.name, mac_address=self.mac_address,
                    power_level=self.get_power_level())

    def get_joystick(self):
        return sdl2.SDL_GameControllerGetJoystick(self.controller)

    def is_present(self):
        return sdl2.SDL_GameControllerGetAttached(self.controller)

    def get_name(self):
        return sdl2.SDL_GameControllerName(self.controller).decode('utf-8')

    def rumble(self, low, high, duration):
        sdl2.SDL_GameControllerRumble(self.controller, low, high, duration)

    def get_axes(self, start=None, end=None, threshold=0.1):
        axes = [sdl2.SDL_GameControllerGetAxis(self.controller, i) for i in range(start or 0, end or sdl2.SDL_CONTROLLER_AXIS_MAX)]
        # Normalize SDL's -32768 to 32767 range to -1.0 to 1.0
        axes = np.array(axes, dtype=np.float32) / 32768.0
        axes = np.where((axes < threshold) & (axes > -threshold), 0, axes)
        return axes

    def normalize_axis_value(self, value):
        return np.float32(value) / 32768.0

    def set_led_color(self, color):
        if hasattr(sdl2, 'SDL_GameControllerSetLED'):
            sdl2.SDL_GameControllerSetLED(
                self.controller, *(np.asarray(color) * 255).astype('int'))

    def get_power_level(self):
        if self.mac_address:
            return int(subprocess.check_output(['cat', glob.glob(f'/sys/class/power_supply/*controller*{self.mac_address}/capacity')[0]]))
        #return sdl2.SDL_JoystickCurrentPowerLevel(self.joystick)

    def disconnect(self):
        if not self.mac_address:
            warnings.warn('Can\'t disconnect gamepad, no mac address available')
            return
        subprocess.check_output(['bluetoothctl',  'disconnect',  self.mac_address])

    def get_buttons(self):
        buttons = [sdl2.SDL_GameControllerGetButton(self.controller, i) for i in range(sdl2.SDL_CONTROLLER_BUTTON_MAX)]
        return np.array(buttons, dtype=np.int32)

    def enable_gyro(self):
        sdl2.SDL_GameControllerSetSensorEnabled(self.controller, sdl2.SDL_SENSOR_GYRO, 1)

    def enable_accel(self):
        sdl2.SDL_GameControllerSetSensorEnabled(self.controller, sdl2.SDL_SENSOR_ACCEL, 1)

    def has_gyro(self):
        return bool(sdl2.SDL_GameControllerHasSensor(self.controller, sdl2.SDL_SENSOR_GYRO))

    def has_accel(self):
        return bool(sdl2.SDL_GameControllerHasSensor(self.controller, sdl2.SDL_SENSOR_ACCEL))

    def get_gyro(self):
        data = np.zeros((3,), dtype=np.float32)
        p = data.ctypes.data_as(ctypes.POINTER(ctypes.c_float))
        sdl2.SDL_GameControllerGetSensorData(self.controller, sdl2.SDL_SENSOR_GYRO, p, 3)
        return data

    def get_accel(self):
        data = np.zeros((3,), dtype=np.float32)
        p = data.ctypes.data_as(ctypes.POINTER(ctypes.c_float))
        sdl2.SDL_GameControllerGetSensorData(self.controller, sdl2.SDL_SENSOR_ACCEL, p, 3)
        return data

    def drop(self):
        sdl2.SDL_GameControllerClose(self.controller)
