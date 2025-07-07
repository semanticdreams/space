class CodeEntity(z.Entity):
    def __init__(self, id, code_str, lang='py', name='', kernel=None, summary=None, project_id=1, autolaunch=0, archived_at=None, launchable=0):
        self.code_str = code_str
        self.lang = lang
        self.name = name
        self.kernel = kernel
        self.summary = summary
        self.project_id = project_id
        self.autolaunch = autolaunch
        self.launchable = launchable
        self.archived_at = archived_at
        super().__init__('code', id)
        self.label = self.name or self.code_str

        self.view = z.CodeEntityView
        self.preview = z.CodeEntityPreview
        self.color = (0.5, 0.3, 0.1, 1)

    @classmethod
    def all(cls):
        return world.apps['Entities'].get_entities('code')

    @classmethod
    def create(cls, project_id=1, code_str='', lang='py', name='', kernel=0, summary=None,
               autolaunch=0, launchable=0, id=None):
        data = {
            'code_str': code_str,
            'name': name,
            'lang': lang,
            'project_id': project_id,
            'kernel': kernel,
            'summary': summary,
            'autolaunch': autolaunch,
            'launchable': launchable,
        }
        id = super().create('code', data, id=id)
        return cls(id, code_str, lang, name, kernel, summary, project_id, autolaunch, launchable=launchable)

    @classmethod
    def load(cls, id, data):
        return cls(id, data['code_str'], data['lang'], data['name'], data['kernel'],
                   data['summary'], data['project_id'], data['autolaunch'], launchable=data.get('launchable', 0),
                   )

    def set_code_str(self, code_str):
        self.code_str = code_str

    def dump_data(self):
        return {
            'code_str': self.code_str,
            'name': self.name,
            'kernel': self.kernel,
            'lang': self.lang,
            'summary': self.summary,
            'project_id': self.project_id,
            'autolaunch': self.autolaunch,
            'launchable': self.launchable
        }

    def clone(self):
        return CodeEntity.create(
            project_id=self.project_id,
            code_str=self.code_str,
            lang=self.lang,
            name=f"Copy of {self.name}" if self.name else "",
            kernel=self.kernel,
            autolaunch=self.autolaunch,
            launchable=self.launchable,
        )

    def run(self, catch_errors=False, callback=None, registers=None, on_write_out=None, on_write_error=None):
        return world.kernels.ensure_kernel(self.kernel).send_code(
            self.to_dict(),
            callback=callback,
            registers=registers,
            catch_errors=catch_errors,
            on_write_out=on_write_out,
            on_write_error=on_write_error
        )

    def update_summary(self, summary):
        self.summary = summary

    def archive(self):
        self.archived_at = time.time()

    def to_dict(self):
        return {
            'id': self.id,
            'code': self.code_str,
            'lang': self.lang,
            'name': self.name,
            'kernel': self.kernel,
            'summary': self.summary,
            'project_id': self.project_id,
            'autolaunch': self.autolaunch,
            'launchable': self.launchable,
            'archived_at': self.archived_at
        }

    #@staticmethod
    #def grep(query):
    #    return list(map(dict, world.db.execute(
    #       'select * from codes where code like ? collate nocase',
    #        (f'%{query}%',)
    #    ).fetchall()))

    #@staticmethod
    #def get_all():
    #    return list(map(dict, world.db.execute(
    #        'select * from codes where archived_at is null order by id desc'
    #    ).fetchall()))

    #@staticmethod
    #def run_autolaunch_codes():
    #    for code in world.db.execute('select * from codes where autolaunch = 1 and archived_at is null'):
    #        code_dict = dict(code)
    #        world.kernels.ensure_kernel(code_dict['kernel']).send_code(code_dict)
