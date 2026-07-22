---
type: index
aliases:
  - Features
tags:
  - index
  - features
---

# Features

```dataview
TABLE status, parent-goal
FROM "knowledge"
WHERE type = "feature" AND status != "shipped"
SORT status ASC, created DESC
```

## Shipped

```dataview
TABLE parent-goal
FROM "knowledge"
WHERE type = "feature" AND status = "shipped"
SORT created DESC
```

## See also

- [[home]] — back to knowledge base index
