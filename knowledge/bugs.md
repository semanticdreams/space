---
type: index
aliases:
  - Bugs
tags:
  - index
  - bugs
---

# Bugs

```dataview
TABLE severity, status
FROM "knowledge"
WHERE type = "bug" AND status != "fixed" AND status != "wont-fix"
SORT severity DESC, created DESC
```

## Fixed

```dataview
TABLE severity
FROM "knowledge"
WHERE type = "bug" AND status = "fixed"
SORT created DESC
```

## See also

- [[home]] — back to knowledge base index
