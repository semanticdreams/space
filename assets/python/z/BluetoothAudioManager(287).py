import subprocess
import re


class BluetoothAudioManager:
    def __init__(self):
        self.card = self.get_bluetooth_audio_card()
        self.headsets = self.get_connected_bluetooth_headsets()
        self.a2dp_profile = None
        self.hsp_profile = None
        if self.card:
            self.detect_available_profiles()

    def get_connected_bluetooth_headsets(self):
        result = subprocess.run(["bluetoothctl", "devices"], capture_output=True, text=True)
        devices = []
        for line in result.stdout.strip().split("\n"):
            match = re.search(r"Device ([\w:]+) (.+)", line)
            if match:
                devices.append({
                    "mac": match.group(1),
                    "name": match.group(2)
                })
        return devices

    def get_bluetooth_audio_card(self):
        result = subprocess.run(["pactl", "list", "cards", "short"], capture_output=True, text=True)
        for line in result.stdout.strip().split("\n"):
            parts = line.split("\t")
            if "bluez" in parts[1]:
                return parts[1]
        return None

    def detect_available_profiles(self):
        result = subprocess.run(["pactl", "list", "cards"], capture_output=True, text=True)
        card_blocks = result.stdout.split("Card #")
        for block in card_blocks:
            if self.card and self.card in block:
                # Extract profiles under the "Profiles:" section
                profiles_section = re.search(r"Profiles:(.*?)(Active Profile|Properties:|$)", block, re.DOTALL)
                if profiles_section:
                    profiles_text = profiles_section.group(1)
                    profiles = re.findall(r"^\s+([^\s:]+):", profiles_text, re.MULTILINE)
                    for profile in profiles:
                        if "a2dp" in profile:
                            self.a2dp_profile = profile
                        elif "headset" in profile or "handsfree" in profile or "hsp" in profile or "hfp" in profile:
                            self.hsp_profile = profile
                break
        print(f"Detected A2DP Profile: {self.a2dp_profile}")
        print(f"Detected HSP/HFP Profile: {self.hsp_profile}")

    def get_current_audio_profile(self):
        if not self.card:
            return None
        result = subprocess.run(["pactl", "list", "cards"], capture_output=True, text=True)
        card_blocks = result.stdout.split("Card #")
        for block in card_blocks:
            if self.card in block:
                profile_match = re.search(r"Active Profile: ([^\n]+)", block)
                if profile_match:
                    return profile_match.group(1).strip()
        return None

    def switch_audio_profile(self, profile_name):
        if not self.card or not profile_name:
            print("No Bluetooth audio card or profile found.")
            return
        subprocess.run(["pactl", "set-card-profile", self.card, profile_name])
        print(f"Switched {self.card} to {profile_name}")

    def switch_to_headset_profile(self):
        self.switch_audio_profile(self.hsp_profile)

    def switch_to_quality_profile(self):
        self.switch_audio_profile(self.a2dp_profile)

    def toggle_profile(self):
        current_profile = self.get_current_audio_profile()
        if not current_profile:
            print("No active profile detected.")
            return
        if current_profile == self.a2dp_profile:
            self.switch_to_headset_profile()
        elif current_profile == self.hsp_profile:
            self.switch_to_quality_profile()
        else:
            print("Unknown profile, defaulting to A2DP.")

    def get_sink(self):
        if not self.card:
            return None
        # Extract the MAC portion from the card name
        mac_part = self.card.replace("bluez_card.", "")  # e.g., AC_3E_B1_86_B4_CB
        result = subprocess.run(["pactl", "list", "sinks"], capture_output=True, text=True)
        sinks = result.stdout.split("Sink #")
        for block in sinks:
            if f"bluez_sink.{mac_part}" in block:
                match = re.search(r"Name: ([^\s]+)", block)
                if match:
                    sink_name = match.group(1)
                    print(f"Detected sink for card {self.card}: {sink_name}")
                    return sink_name
        return None

    def force_transport_reconnect(self):
        sink = self.get_sink()
        subprocess.run(["pactl", "suspend-sink", sink, "1"])
        subprocess.run(["pactl", "suspend-sink", sink, "0"])

    def status(self):
        print(f"Detected headset(s): {[d['name'] for d in self.headsets] if self.headsets else 'None'}")
        print(f"Bluetooth audio card: {self.card if self.card else 'None'}")
        print(f"Current profile: {self.get_current_audio_profile() if self.card else 'N/A'}")

    def drop(self):
        pass


if __name__ == "__main__":
    manager = BluetoothAudioManager()
    manager.status()
    manager.toggle_profile()
    manager.force_transport_reconnect()
