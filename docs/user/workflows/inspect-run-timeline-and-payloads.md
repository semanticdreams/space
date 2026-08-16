# Inspect a run timeline and payloads without flooding the graph

Goal: understand what happened in a workflow run while materializing only the details you need.

1. Open a workflow definition and use its run search to find the run you want to inspect.
2. Open the workflow run node.
3. Choose **Open Timeline**. Space opens `workflow-run-timeline:<run-id>` so you can browse ordered events without materializing every event node by default.
4. Use timeline event search to materialize one event when that event needs graph context.
5. Choose **Show Run Steps** only when all run steps are useful to see as graph nodes.
6. Open run-step and event full views for multiline payloads, logs, outputs, and errors. Dense JSON, Fennel forms, and long text belong in editor-style panels, not single-line preview labels.
7. Use **Cancel Run** only when the run status supports cancellation. Completed and otherwise non-cancellable runs do not show that action.
8. If the visible working set becomes too dense, remove graph nodes manually from the map. Manual cleanup preserves the rule that materialization is explicit and map-local.

You are done when the timeline and selected payload views answer the run question without turning the graph into an indiscriminate event dump.
