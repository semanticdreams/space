# Graph vs Entities

Idea 1: Graph-only, make each node have its own storage backend logic.
- Linking nodes persistently based on key is a graph feature.

Idea 2: Entities mounted into graph.
- Graph entity used to connect entities
- Graph entity mounted into space graph
- Entities can wrap other stuff that graph would normally show directly
- entities may use common storage but could also have individual storage logic

=> the difference is only whether there is a common abstraction for entities
