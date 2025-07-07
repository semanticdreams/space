import os
import json
import keyring
from keyring.backends import SecretService
from cryptography.fernet import Fernet

keyring.set_keyring(SecretService.Keyring())


class Secrets:
    def __init__(self):
        self.path = os.path.join(world.datadir, 'secrets')
        self.secrets = None
        self.key = None

    def ensure_key(self):
        if self.key is None:
            user = 'secrets-encryption-key'
            self.key = keyring.get_password('space', user)
            if self.key is None:
                self.key = Fernet.generate_key()
                keyring.set_password('space', user, self.key.decode())

    def save(self):
        self.ensure_key()
        plain_content = json.dumps(self.secrets)
        cipher_suite = Fernet(self.key)
        content = cipher_suite.encrypt(plain_content.encode()).decode()
        with open(self.path, 'w') as f:
            f.write(content)

    def load(self):
        self.ensure_key()
        if not os.path.isfile(self.path):
            self.secrets = {}
            return
        with open(self.path) as f:
            content = f.read()
        cipher_suite = Fernet(self.key)
        plain_content = cipher_suite.decrypt(content.encode()).decode()
        self.secrets = json.loads(plain_content)

    def get(self, name):
        if self.secrets is None:
            self.load()
        return self.secrets[name]

    def set(self, name, secret):
        if self.secrets is None:
            self.load()
        self.secrets[name] = secret
        self.save()

    def drop(self):
        pass
