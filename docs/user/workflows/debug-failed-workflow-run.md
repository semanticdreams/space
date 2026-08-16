# Find and fix the workflow step that caused a failed run

Goal: diagnose a failed workflow run, repair the underlying step code, and compare the next run against the failure.

1. Open the workflow definition from **Start -> Workflows**.
2. Use the definition's run search to find the failed run by status, time, or label, then open that run node.
3. Choose **Reveal Failed Steps** on the run node. This materializes only failed run-step nodes instead of dumping every run detail into the graph.
4. Open the failed run-step payload panel. Inspect multiline inputs, outputs, logs, and errors in the full view so long payloads are readable.
5. Follow the failed run-step link back to the workflow step. From the workflow-step node, choose **Show Code** to open the linked code entity.
6. Edit the step code in the code view. Keep the graph focused on the failed path while the full code view handles the dense editor interaction.
7. Return to the workflow definition and choose **Start** to create a new run.
8. Open the new run's timeline and compare its events/status with the failed run. The new timeline should show the repaired step reaching the expected state.

You are done when the new run no longer fails at the repaired step, or when the new timeline identifies the next specific step to fix.
