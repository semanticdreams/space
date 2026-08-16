# Monitor and cancel a running workflow

Goal: watch an in-progress workflow and cancel it only when cancellation is a valid run action.

1. Start a workflow from its definition node, or open an already in-progress workflow run from the definition's run search.
2. Read the current status from the workflow run node. The run preview shows whether the run is pending, running, completed, failed, or cancellable.
3. Choose **Open Timeline** to watch progress. The timeline lets you inspect ordered events without materializing every event in the graph.
4. Use **Show Run Steps** when you need graph context for the current execution path. Reveal run steps deliberately rather than flooding the map by default.
5. Use **Cancel Run** only when the run status supports cancellation. The action is explicit because it changes the underlying run.
6. Verify cancellation through the run node status and timeline events. A cancelled run should show cancellation status and a corresponding event trail.
7. For completed, failed, or otherwise non-cancellable runs, recognize that **Cancel Run** is not shown. Inspect the timeline or payloads instead.

You are done when the running workflow either reaches a terminal status naturally or shows a clear cancelled status with timeline evidence.
