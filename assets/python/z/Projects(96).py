class Projects:
    def get_projects(self):
        return list(map(dict, world.db.execute('select * from projects').fetchall()))

    def get_project(self, id):
        return dict(one(world.db.execute('select * from projects'
                                         ' where id = ?',
                                         (id,)).fetchall()))
    def create_folder(self, project):
        folder = world.folders.create_folder(f'project-{project["name"]}')
        with world.db:
            world.db.execute('update projects set folder_id = ? where id = ?',
                             (folder['id'], project['id']))
        return folder

    def ensure_folder(self, project):
        folder = self.get_folder(project) or self.create_folder(project)
        return folder

    def get_folder(self, project):
        return world.folders.get_folder(project['folder_id']) if project.get('folder_id') else None

    def create_project(self):
        with world.db:
            cur = world.db.execute('insert into projects default values')
        return self.get_project(cur.lastrowid)

    def update_project_name(self, id, name):
        with world.db:
            world.db.execute('update projects set name = ? where id = ?',
                             (name, id))