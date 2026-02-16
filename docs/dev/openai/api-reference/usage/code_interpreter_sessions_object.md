# Code interpreter sessions usage object

The aggregated code interpreter sessions usage details of the specific time bucket.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.usage.code_interpreter_sessions.result` |  |
| `num_sessions` | integer | No |  |  | The number of code interpreter sessions. |
| `project_id` | string | No |  |  | When `group_by=project_id`, this field provides the project ID of the grouped usage result. |

## Property Details

### `object` (required)

**Type**: string

**Allowed values**: `organization.usage.code_interpreter_sessions.result`

### `num_sessions`

The number of code interpreter sessions.

**Type**: integer

### `project_id`

When `group_by=project_id`, this field provides the project ID of the grouped usage result.

**Type**: string

**Nullable**: Yes

## Example

```json
{
    "object": "organization.usage.code_interpreter_sessions.result",
    "num_sessions": 1,
    "project_id": "proj_abc"
}

```

