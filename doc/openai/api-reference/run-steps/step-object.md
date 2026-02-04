# The run step object

Represents a step in execution of a run.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier of the run step, which can be referenced in API endpoints. |
| `object` | string | Yes |  | `thread.run.step` | The object type, which is always `thread.run.step`. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step was created. |
| `assistant_id` | string | Yes |  |  | The ID of the [assistant](/docs/api-reference/assistants) associated with the run step. |
| `thread_id` | string | Yes |  |  | The ID of the [thread](/docs/api-reference/threads) that was run. |
| `run_id` | string | Yes |  |  | The ID of the [run](/docs/api-reference/runs) that this run step is a part of. |
| `type` | string | Yes |  | `message_creation`, `tool_calls` | The type of run step, which can be either `message_creation` or `tool_calls`. |
| `status` | string | Yes |  | `in_progress`, `cancelled`, `failed`, `completed`, `expired` | The status of the run step, which can be either `in_progress`, `cancelled`, `failed`, `completed`, or `expired`. |
| `step_details` | object | Yes |  |  | The details of the run step. |
| `last_error` | object (2 properties) | Yes |  |  | The last error associated with this run step. Will be `null` if there are no errors. |
| `expired_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step expired. A step is considered expired if the parent run is expired. |
| `cancelled_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step was cancelled. |
| `failed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step failed. |
| `completed_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the run step completed. |
| `metadata` | map | Yes |  |  | Set of 16 key-value pairs that can be attached to an object. This can be <br> useful for storing additional information about the object in a structured <br> format, and querying for objects via API or the dashboard.  <br>  <br> Keys are strings with a maximum length of 64 characters. Values are strings <br> with a maximum length of 512 characters. <br>  |
|   ↳ (additional properties) | string | - | - | - | Additional properties of this object |
| `usage` | object (3 properties) | Yes |  |  | Usage statistics related to the run step. This value will be `null` while the run step's status is `in_progress`. |
|   ↳ `total_tokens` | integer | Yes |  |  | Total number of tokens used (prompt + completion). |

## Property Details

### `id` (required)

The identifier of the run step, which can be referenced in API endpoints.

**Type**: string

### `object` (required)

The object type, which is always `thread.run.step`.

**Type**: string

**Allowed values**: `thread.run.step`

### `created_at` (required)

The Unix timestamp (in seconds) for when the run step was created.

**Type**: integer

### `assistant_id` (required)

The ID of the [assistant](/docs/api-reference/assistants) associated with the run step.

**Type**: string

### `thread_id` (required)

The ID of the [thread](/docs/api-reference/threads) that was run.

**Type**: string

### `run_id` (required)

The ID of the [run](/docs/api-reference/runs) that this run step is a part of.

**Type**: string

### `type` (required)

The type of run step, which can be either `message_creation` or `tool_calls`.

**Type**: string

**Allowed values**: `message_creation`, `tool_calls`

### `status` (required)

The status of the run step, which can be either `in_progress`, `cancelled`, `failed`, `completed`, or `expired`.

**Type**: string

**Allowed values**: `in_progress`, `cancelled`, `failed`, `completed`, `expired`

### `step_details` (required)

The details of the run step.

**Type**: object

### `last_error` (required)

The last error associated with this run step. Will be `null` if there are no errors.

**Type**: object (2 properties)

**Nullable**: Yes

**Nested Properties**:

* `code`, `message`

### `expired_at` (required)

The Unix timestamp (in seconds) for when the run step expired. A step is considered expired if the parent run is expired.

**Type**: integer

**Nullable**: Yes

### `cancelled_at` (required)

The Unix timestamp (in seconds) for when the run step was cancelled.

**Type**: integer

**Nullable**: Yes

### `failed_at` (required)

The Unix timestamp (in seconds) for when the run step failed.

**Type**: integer

**Nullable**: Yes

### `completed_at` (required)

The Unix timestamp (in seconds) for when the run step completed.

**Type**: integer

**Nullable**: Yes

### `metadata` (required)

Set of 16 key-value pairs that can be attached to an object. This can be
useful for storing additional information about the object in a structured
format, and querying for objects via API or the dashboard. 

Keys are strings with a maximum length of 64 characters. Values are strings
with a maximum length of 512 characters.


**Type**: map

**Nullable**: Yes

### `usage` (required)

Usage statistics related to the run step. This value will be `null` while the run step's status is `in_progress`.

**Type**: object (3 properties)

**Nullable**: Yes

**Nested Properties**:

* `completion_tokens`, `prompt_tokens`, `total_tokens`

## Example

```json
{
  "id": "step_abc123",
  "object": "thread.run.step",
  "created_at": 1699063291,
  "run_id": "run_abc123",
  "assistant_id": "asst_abc123",
  "thread_id": "thread_abc123",
  "type": "message_creation",
  "status": "completed",
  "cancelled_at": null,
  "completed_at": 1699063291,
  "expired_at": null,
  "failed_at": null,
  "last_error": null,
  "step_details": {
    "type": "message_creation",
    "message_creation": {
      "message_id": "msg_abc123"
    }
  },
  "usage": {
    "prompt_tokens": 123,
    "completion_tokens": 456,
    "total_tokens": 579
  }
}

```

