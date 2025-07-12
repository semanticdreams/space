class Apps:
    def __init__(self):
        self.apps = []
        self.names = {}
        self.apps_changed = z.Signal()

    def run_autostart_apps(self):
        self.load_app('Entities')
        self.load_app('Shaders')
        self.load_app('Renderers')
        self.load_app('FocusSystem')
        self.load_app('SystemCursors')
        self.load_app('Themes')
        self.load_app('Icons')
        self.load_app('States')
        self.load_app('CombinedMouseControl')
        self.load_app('Vim')
        self.load_app('Time')
        self.load_app('Store')
        self.load_app('CameraApp')
        self.load_app('Clipboard')
        self.load_app('Charts')
        self.load_app('Lines')
        self.load_app('Secrets')
        self.load_app('Clickables')
        self.load_app('Hoverables')
        self.load_app('Menus')
        self.load_app('Hud')
        self.load_app('EntityIndicator')
        #self.load_app('Claude')
        #self.load_app('ClaudeIndicator')
        self.load_app('TasksIndicator')
        self.load_app('BackupIndicator')
        self.load_app('DaysSinceBirthIndicator')
        self.load_app('Floaties')
        self.load_app('FloatiesIndicator')
        self.load_app('AppsApp')
        self.load_app('ErrorViews')
        self.load_app('Spatiolation')
        self.load_app('ObjectSelector')
        self.load_app('Dialogs')
        self.load_app('Consoles')
        self.load_app('Codebooks')
        self.load_app('LaunchableCodes')
        self.load_app('ThemeIndicator')
        self.load_app('SpeechRecorderIndicator')
        self.load_app('WorldIndicator')
        self.load_app('StatesIndicator')
        #self.load_app('FocusIndicator')
        self.load_app('LauncherApp')
        self.load_app('OriginPoint')
        self.load_app('CodesApp')
        #self.load_app('ClaudeApp')
        self.load_app('Workspaces')
        self.load_app('WorkspaceIndicator')
        self.load_app('ApplicationKeyMenuLauncher')
        self.load_app('VimIndicator')
        self.load_app('FileSystemApp')
        #self.load_app('Notes')
        #self.load_app('Notebooks')
        #self.load_app('NotebooksApp')
        self.load_app('Circles')
        self.load_app('DefaultViews')
        self.load_app('BluetoothAudioManager')
        self.load_app('KernelsSnacks')
        #self.load_app('FlatGround')
        self.load_app('DynamicGraphApp')
        self.load_app('LuaWorldApp')

    def __getitem__(self, key):
        if key in self.names:
            return self.names[key]
        raise Exception(f'{key} not in apps')
        #return super().__getitem__(key)

    def load_app(self, key):
        cls = world.classes[key]
        obj = cls()
        assert hasattr(obj, 'drop'), obj
        self.add_app(obj)
        return obj

    def ensure_app(self, key):
        if key not in self.names:
            self.load_app(key)
        return self.names[key]

    def reload_app(self, key, emit_changed=True):
        self.drop_app(self[key], emit_changed=False)
        self.load_app(key)
        if emit_changed:
            self.apps_changed.emit()

    def add_app(self, app):
        self.apps.append(app)
        self.names[app.__class__.__name__] = app
        self.apps_changed.emit()

    def drop_app(self, app, emit_changed=True):
        app.drop()
        self.apps.remove(app)
        self.names.pop(app.__class__.__name__)
        if emit_changed:
            self.apps_changed.emit()

    def reload(self):
        self.drop()
        self.run_autostart_apps()
        self.apps_changed.emit()

    def drop(self):
        for app in reversed(self.apps):
            app.drop()
        self.names.clear()
        self.apps.clear()
