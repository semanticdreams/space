import os
import time
import json


class Icons:
    def __init__(self):
        d = os.path.join(world.assets_path, 'material-design-icons')
        self.font = z.Font(os.path.join(d, 'msdf/icons.png'),
                           os.path.join(d, 'msdf/icons.json'))
        self.codepoints = dict(x.split() for x in open(os.path.join(d, 'MaterialSymbolsSharp[FILL,GRAD,opsz,wght].codepoints')).read().strip().split('\n'))

    def __getitem__(self, key):
        return int('0x' + self.codepoints[key], 16)

    def drop(self):
        self.font.drop()
