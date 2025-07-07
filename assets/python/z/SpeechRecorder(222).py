import os
import speech_recognition as sr


class SpeechRecorder:
    def __init__(self, bluetooth=True):
        self.bluetooth = bluetooth
        self.recognizer = sr.Recognizer()
        if 'speech_recognizer/energy_threshold' in world.settings.values:
            self.recognizer.energy_threshold = float(world.settings.get_value('speech_recognizer/energy_threshold'))
        self.microphone = sr.Microphone()

        self.device = 'cpu'
        if self.device == 'cpu':
            os.environ['OMP_NUM_THREADS'] = str(4)
            self.compute_type = 'int8'
        else:
            self.compute_type = 'float16'
        self.model = 'tiny.en' # for en: tiny, base, small, medium

    def adjust_for_ambient_noise(self):
        if self.bluetooth:
            world.apps['BluetoothAudioManager'].switch_to_headset_profile()
        with self.microphone:
            self.recognizer.adjust_for_ambient_noise(self.microphone)
        world.settings.set_value('speech_recognizer/energy_threshold', str(self.recognizer.energy_threshold))
        if self.bluetooth:
            world.apps['BluetoothAudioManager'].switch_to_quality_profile()

    def listen(self):
        if self.bluetooth:
            world.apps['BluetoothAudioManager'].switch_to_headset_profile()
        with self.microphone:
            audio = self.recognizer.listen(self.microphone)
        if self.bluetooth:
            world.apps['BluetoothAudioManager'].switch_to_quality_profile()
        return audio

    def recognize(self, audio):
        value = self.recognizer.recognize_faster_whisper(
            audio, model=self.model, init_options=dict(device=self.device, compute_type=self.compute_type),
            show_dict=True, language='en', initial_prompt='')
        return value

    def listen_and_recognize(self):
        v = self.recognize(self.listen())
        return v

    def drop(self):
        pass
