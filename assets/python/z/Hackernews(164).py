import os
import json
import asyncio
from lib.requests import requests
class Hackernews:
    def __init__(self):
        self.baseurl = 'https://hacker-news.firebaseio.com/v0/'
        self.items = {}

        self.data_folder = os.path.join(world.datadir, 'hackernews')
        os.makedirs(self.data_folder, exist_ok=True)

        self.items_folder = os.path.join(self.data_folder, 'items')
        os.makedirs(self.items_folder, exist_ok=True)
        self.saved_stories_path = os.path.join(self.data_folder, 'saved-stories.json')

    async def get_item(self, id):
        if id in self.items:
            return self.items[id]
        item_filename = os.path.join(self.items_folder, '{}.json'.format(id))
        if os.path.exists(item_filename):
            with open(item_filename) as f:
                item = json.load(f)
                self.items[id] = item
                return item
        url = self.baseurl + 'item/{}.json'.format(id)
        response = await requests.get(url)
        item = await response.json()
        self.items[id] = item
        with open(item_filename, 'w') as f:
            json.dump(item, f)
        return item

    async def get_items(self, ids):
        return await asyncio.gather(*[self.get_item(id) for id in ids])

    async def get_stories(self, category):
        assert category in ('topstories', 'newstories', 'beststories')
        url = self.baseurl + f'{category}.json'
        response = await requests.get(url)
        item_ids = await response.json()
        return await self.get_items(item_ids)

    async def get_story_comments(self, story):
        kids_ids = story.get('kids', [])
        return await self.get_items(kids_ids)

    async def save_story(self, story_id):
        path = self.saved_stories_path
        if os.path.isfile(path):
            with open(path) as f:
                saved = set(json.load(f))
        else:
            saved = set()
        saved.add(story_id)
        with open(path, 'w') as f:
            json.dump(list(saved), f)

    async def get_saved_stories(self):
        with open(self.saved_stories_path) as f:
            ids = json.load(f)
        return await self.get_items(ids)
