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

    def edit_string(self, initial_string, file_suffix=''):
        # Create a temporary file
        with tempfile.NamedTemporaryFile(mode='w+', delete=False, suffix=file_suffix) as temp_file:
            # Write the initial string to the file
            temp_file_name = temp_file.name
            temp_file.write(initial_string)

        # Open Kitty terminal with Vim
        try:
            #subprocess.run(['xfce4-terminal', '--disable-server', '-x', 'vim', temp_file_name], check=True)
            subprocess.run(['gnome-terminal', '--wait', '--', 'vim', temp_file_name], check=True)
        except subprocess.CalledProcessError:
            print("Failed to open Kitty with Vim")
            return None

        # Read the edited content
        with open(temp_file_name, 'r') as temp_file:
            edited_string = temp_file.read()

        return edited_string

    def edit_file(self, path):
        try:
            #subprocess.run(['xfce4-terminal', '-x', 'vim', path], check=True)
            subprocess.run(['kitty', 'vim', path], check=True)
        except subprocess.CalledProcessError:
            print("Failed to open Kitty with Vim")
            return None

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
