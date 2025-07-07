def setup_db(db):
    with db:
        db.execute("""
                   CREATE TABLE if not exists "cameras" (
                   "id"	INTEGER,
                   "position"	TEXT,
                   "rotation"	TEXT,
                   "name"	TEXT,
                   PRIMARY KEY("id" AUTOINCREMENT)
                  )
                  """)

        # Check if a camera with id 0 exists
        cur = db.execute('SELECT 1 FROM cameras WHERE id = 0')
        if cur.fetchone() is None:
            # Insert default camera with id 0
            db.execute('INSERT INTO cameras (id, position, rotation, name) VALUES (?, ?, ?, ?)',
                       (0, json.dumps([0, 0, 0]), json.dumps([1, 0, 0, 0]), 'default'))

        db.execute("""
                   create table if not exists "kernels" (
                   "id" integer,
                   "cmd" text,
                   "cwd" text,
                   "name" text,
                   primary key("id" autoincrement)
                  )""")

        db.execute("""
                   create table if not exists "settings" (
                   "key" text,
                   "value" text,
                   primary key("key")
                  )""")

        db.execute("""
                   CREATE TABLE if not exists "schedules" (
                   "id"	INTEGER,
                   "start_at"	INTEGER,
                   "end_at"	INTEGER,
                   "weekday"	TEXT,
                   "monthday"	INTEGER,
                   "frequency"	TEXT NOT NULL,
                   "interval"	INTEGER NOT NULL DEFAULT 1,
                   "monthweek"	INTEGER,
                   "yearmonth"	INTEGER,
                   PRIMARY KEY("id" AUTOINCREMENT)
                  )
                   """)
        cur = db.execute("""
                   CREATE TABLE if not exists "default_views" (
                   "id"	INTEGER,
                   "type_name"	TEXT,
                   "view_class_name"	TEXT,
                   "pos"	INTEGER DEFAULT 0,
                   "created_at"	INTEGER,
                   "updated_at"	INTEGER,
                   PRIMARY KEY("id" AUTOINCREMENT)
                  )
                   """)
        if db.execute('select 1 from default_views').fetchone() is None:
            items = [
                ('dict', 'PyDictView'),
                ('type', 'ClassView'),
                ('list', 'ListView'),
                ('list', 'SearchView'),
                ('zip', 'SearchView'),
                ('list', 'SearchViewFromList'),
            ]
            for type_name, view_class_name in items:
                db.execute('insert into default_views (type_name, view_class_name, created_at, updated_at) values (?, ?, ?, ?)',
                           (type_name, view_class_name, time.time(), time.time()))

        db.execute("""
                   CREATE TABLE if not exists "entities" (
                   "id"	TEXT,
                   "type"	BLOB NOT NULL,
                   "data"	TEXT,
                   "created_at"	REAL,
                   "updated_at"	REAL,
                   PRIMARY KEY("id")
                  )
                   """)

        #db.execute("""
        #           create table if not exists entity_tags (
        #           tag_entity_id text,
        #           target_entity_id text,
        #           primary key (tag_entity_id, target_entity_id)
        #          )
        #           """)

