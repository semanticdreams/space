---
type: index
aliases:
  - Ideas
tags:
  - index
  - ideas
---

# Ideas

```dataview
LIST
FROM "knowledge"
WHERE type = "idea" AND status != "archived"
SORT status ASC, created DESC
```

## Archived

```dataview
LIST
FROM "knowledge"
WHERE type = "idea" AND status = "archived"
SORT created DESC
```

## See also

- [[home]] — back to knowledge base index
