import re
import xml.etree.ElementTree as ET
from collections import defaultdict


class XML:
    def __init__(self, text):
        self._raw = text
        self._tag_map = None  # Lazy-load upon first access
        self.elements = []

    def _parse_tags(self):
        self._tag_map = defaultdict(list)
        pattern = r"<(?P<tag>\w+)[^>]*?>.*?</(?P=tag)>"
        for match in re.finditer(pattern, self._raw, re.DOTALL):
            xml_snippet = match.group(0)
            try:
                element = ET.fromstring(xml_snippet)
                self._tag_map[element.tag].append(element)
                self.elements.append(element)
            except ET.ParseError:
                continue

    def ensure_parsed(self):
        if self._tag_map is None:
            self._parse_tags()

    def __getattr__(self, tag):
        self.ensure_parsed()
        return self._tag_map.get(tag, [])

    def set_text(self, new_text):
        """Replaces the entire raw text and resets parsing state."""
        self._raw = new_text
        self._tag_map = None  # Reset so it re-parses lazily on next access
        self.elements.clear()