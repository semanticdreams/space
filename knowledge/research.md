---
type: index
aliases:
  - Research
tags:
  - index
  - research
---

# Research

```dataview
LIST
FROM "knowledge"
WHERE type = "research" AND status != "closed"
SORT created DESC
```

## Closed

```dataview
LIST
FROM "knowledge"
WHERE type = "research" AND status = "closed"
SORT created DESC
```

## See also

- [[home]] — back to knowledge base index
