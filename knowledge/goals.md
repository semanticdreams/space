---
type: index
aliases:
  - Goals
tags:
  - index
  - goals
---

# Goals

```dataview
LIST
FROM "knowledge"
WHERE type = "goal" AND status != "done"
SORT status ASC, created DESC
```

## Completed

```dataview
LIST
FROM "knowledge"
WHERE type = "goal" AND status = "done"
SORT created DESC
```

## See also

- [[home]] — back to knowledge base index
