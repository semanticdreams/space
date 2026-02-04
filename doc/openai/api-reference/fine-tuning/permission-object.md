# The fine-tuned model checkpoint permission object

The `checkpoint.permission` object represents a permission for a fine-tuned model checkpoint.


## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The permission identifier, which can be referenced in the API endpoints. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the permission was created. |
| `project_id` | string | Yes |  |  | The project identifier that the permission is for. |
| `object` | string | Yes |  | `checkpoint.permission` | The object type, which is always "checkpoint.permission". |

## Property Details

### `id` (required)

The permission identifier, which can be referenced in the API endpoints.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) for when the permission was created.

**Type**: integer

### `project_id` (required)

The project identifier that the permission is for.

**Type**: string

### `object` (required)

The object type, which is always "checkpoint.permission".

**Type**: string

**Allowed values**: `checkpoint.permission`

## Example

```json
{
  "object": "checkpoint.permission",
  "id": "cp_zc4Q7MP6XxulcVzj4MZdwsAB",
  "created_at": 1712211699,
  "project_id": "proj_abGMw1llN8IrBb6SvvY5A1iH"
}

```

