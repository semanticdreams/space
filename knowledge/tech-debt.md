---
type: index
aliases:
  - Tech Debt
tags:
  - index
  - tech-debt
---

# Technical Debt

```dataview
TABLE impact, effort, status
FROM "knowledge"
WHERE type = "tech-debt" AND status != "resolved"
SORT impact DESC, created DESC
```

## Resolved

```dataview
TABLE impact, effort
FROM "knowledge"
WHERE type = "tech-debt" AND status = "resolved"
SORT created DESC
```

## See also

- [[home]] — back to knowledge base index
