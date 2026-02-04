import re
import tempfile
import subprocess


class Dialogs:
    def edit_color_with_zenity(self, initial_color=None):
        # Convert the color to a string
        initial_color_string = '#%02x%02x%02x' % tuple(int(255 * c) for c in initial_color[:3])

        # Open Zenity color picker
        try:
            completed_process = subprocess.run(['zenity', '--color-selection', '--show-palette', '--color=' + initial_color_string], check=True, stdout=subprocess.PIPE)
        except subprocess.CalledProcessError:
            print("Failed to open Zenity color picker")
            return None

        # Read the edited content
        edited_color_string = completed_process.stdout.decode('utf-8').strip()

        # Extract RGB values from the string
        match = re.match(r'rgb\((\d+),(\d+),(\d+)\)', edited_color_string)
        if not match:
            print("Invalid color format")
            return None

        edited_color = tuple(int(match.group(i)) / 255 for i in range(1, 4))

        return (*edited_color, initial_color[3])

    def error_message_box(self, message):
        subprocess.run(['zenity', '--error', '--text', message], check=True)

    def confirm_message_box(self, message):
        p = subprocess.run(['zenity', '--question', '--text', message], check=False, capture_output=True)
        return p.returncode == 0

    def choose_item_with_zenity(self, items):
        formatted_items = [y for x in enumerate(items) for y in [str(x[0]), x[1]]]
        p = subprocess.run(['zenity', '--list', *formatted_items, '--column=id', '--column=Select your choice', '--hide-column=1', '--print-column=1'], stdout=subprocess.PIPE, check=True)
        return int(p.stdout.decode('utf-8').strip())

    def drop(self):
        pass
