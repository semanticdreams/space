# The run step delta object

Represents a run step delta i.e. any changed fields on a run step during streaming.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier of the run step, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `thread.run.step.delta` | The object type, which is always `thread.run.step.delta`. |
| `delta` | object (1 property) | Yes |  |  | The delta containing the fields that have changed on the run step. |

## Property Details

### `id` (required)

The identifier of the run step, which can be referenced in API endpoints.

**Type**: string

### `object` (required)

The object type, which is always `thread.run.step.delta`.

**Type**: string

**Allowed values**: `thread.run.step.delta`

### `delta` (required)

The delta containing the fields that have changed on the run step.

**Type**: object (1 property)

**Nested Properties**:

* `step_details`

## Example

```json
{
  "id": "step_123",
  "object": "thread.run.step.delta",
  "delta": {
    "step_details": {
      "type": "tool_calls",
      "tool_calls": [
        {
          "index": 0,
          "id": "call_123",
          "type": "code_interpreter",
          "code_interpreter": { "input": "", "outputs": [] }
        }
      ]
    }
  }
}

```

