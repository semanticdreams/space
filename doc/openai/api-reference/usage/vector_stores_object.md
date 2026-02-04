# Vector stores usage object

The aggregated vector stores usage details of the specific time bucket.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.usage.vector_stores.result` |  |
| `usage_bytes` | integer | Yes |  |  | The vector stores usage in bytes. |
| `project_id` | string | No |  |  | When `group_by=project_id`, this field provides the project ID of the grouped usage result. |

## Property Details

### `object` (required)

**Type**: string

**Allowed values**: `organization.usage.vector_stores.result`

### `usage_bytes` (required)

The vector stores usage in bytes.

**Type**: integer

### `project_id`

When `group_by=project_id`, this field provides the project ID of the grouped usage result.

**Type**: string

**Nullable**: Yes

## Example

```json
{
    "object": "organization.usage.vector_stores.result",
    "usage_bytes": 1024,
    "project_id": "proj_abc"
}

```

