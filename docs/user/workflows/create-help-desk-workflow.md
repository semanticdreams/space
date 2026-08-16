# Create a help desk workflow from scratch

Goal: build a small help desk workflow that triages an incoming ticket, drafts a response, and records the result.

1. Open **Start -> Workflows**. The Workflows root shows workflow definitions without expanding every run or step.
2. Choose **New Workflow**. Name it for the help desk flow. Space creates the workflow definition and materializes the new definition node in the active graph map.
3. Find the workflow definition node in the graph. Its preview is the anchor for authoring, running, and inspecting this workflow.
4. Use **New Step** to add the first triage step. The action materializes the workflow-step node and its linked code entity so the next edit is visible.
5. On the step node, choose **Show Code**. Open the code entity and edit the step in the code view, for example to classify the ticket by urgency and department.
6. Repeat **New Step** for the draft-response and record-result steps. Use **Show Code** on each step for surgical code edits in the code view rather than cramming source into the preview.
7. Choose **Reveal All Steps** from the workflow definition when you are ready to see the topology. The graph materializes the workflow-step nodes and derived workflow display edges.
8. Connect the step nodes with graph edges in the order the help desk process should run: triage -> draft response -> record result. These authored edges update the canonical workflow edges in the workflow store.
9. Choose **Start** from the workflow definition node to create a run. The run node appears in the graph with a definition-to-run relationship.
10. Open the run node and inspect its result state. Use the run status and timeline entry points to confirm whether the help desk workflow completed, failed, or is still running.

You are done when the graph shows the workflow definition, connected step nodes, linked code nodes for the edited steps, and a run node whose status reflects the trial run.
