# Use selected graph nodes as workflow run context

Goal: run a workflow against the objects you already selected in the active graph map.

1. In the graph, select the nodes that should become run context. For example, select a ticket entity, customer record, or code node that the workflow should process.
2. Open the workflow definition node for the workflow you want to run.
3. Start the workflow from the definition node using the graph-selection-aware launch path. The launch action reads the active `GraphMap` selection.
4. Confirm the created run records the graph-map id and selected node keys when that context is available. The run node should make the selected context inspectable instead of silently discarding it.
5. Open the run timeline or payload panel to verify the workflow used the selected graph nodes as input context.
6. If the selection is empty or contains unsupported node types, expect an explicit graph-native failure or status message. Fix the selection and launch again; invalid selections must not become silent no-ops.

You are done when the run node, timeline, or payload panel shows the workflow received the intended selected graph-node context.
