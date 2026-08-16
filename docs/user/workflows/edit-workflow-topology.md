# Edit workflow topology with graph step nodes

Goal: change how an existing workflow moves from one step to the next while keeping the graph view focused on the topology you are editing.

1. Open **Start -> Workflows**, search for the existing workflow, and open its workflow definition node.
2. Use step search in the definition preview to reveal one step that you know belongs near the change. The graph materializes only that workflow-step node.
3. Use **Reveal All Steps** when you need the visual topology. Space materializes all steps for the definition and the visible workflow-derived edges between them.
4. If the definition preview is too small for the investigation, choose **Open Step Explorer**. The `workflow-step-explorer:<definition-id>` node gives a focused step browsing surface without owning workflow records.
5. Connect compatible workflow-step nodes in the graph to create canonical workflow edges. The graph edge is the editing gesture; the workflow store remains the owner of the real workflow topology.
6. Remove an authored step edge from the graph to remove the corresponding canonical workflow edge. Do this deliberately, because edge removal changes the workflow's execution path.
7. When a topology change requires a code change, open the affected step node and choose **Show Code**. Edit the linked code node in its code view.
8. Check the visible derived workflow edges after each change. They should match the current workflow topology and omit stale paths you removed.

You are done when the graph's step nodes and visible workflow edges show the execution order you intend, and the linked code nodes contain any matching step edits.
