import os
import json
import argparse
import appdirs
import sqlite3


data_dir = appdirs.user_data_dir('space')
db_path = os.path.join(data_dir, 'space.db')
db = sqlite3.connect(db_path)
db.row_factory = sqlite3.Row

seed_dir = './assets/seed'


def dump_seed():
    print("Dumping seed...")
    for i, row in enumerate(db.execute('select * from entities')):
        path = os.path.join(seed_dir, row['id'] + '.json')
        with open(path, 'w') as f:
            json.dump(dict(row), f)
    print(f'{i+1} entities dumped.')


def load_seed():
    print("Loading seed...")
    inserted_count = 0
    with db:
        cursor = db.cursor()
        for filename in os.listdir(seed_dir):
            path = os.path.join(seed_dir, filename)
            with open(path) as f:
                data = json.load(f)
                cursor.execute(
                    'INSERT OR IGNORE INTO entities'
                    ' (id, type, data, created_at, updated_at)'
                    ' VALUES (?, ?, ?, ?, ?)',
                    (data['id'], data['type'], data['data'], data['created_at'],
                     data['updated_at'])
                )
                if cursor.rowcount:
                    inserted_count += 1
    print(f'{inserted_count} entities inserted.')


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["dump", "load"])
    args = parser.parse_args()

    if args.command == "dump":
        dump_seed()
    elif args.command == "load":
        load_seed()

