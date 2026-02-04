# The project object

Represents an individual project.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `object` | string | Yes |  | `organization.project` | The object type, which is always `organization.project` |
| `name` | string | Yes |  |  | The name of the project. This appears in reporting. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the project was created. |
| `archived_at` | integer | No |  |  | The Unix timestamp (in seconds) of when the project was archived or `null`. |
| `status` | string | Yes |  | `active`, `archived` | `active` or `archived` |

## Property Details

### `id` (required)

The identifier, which can be referenced in API endpoints

**Type**: string

### `object` (required)

The object type, which is always `organization.project`

**Type**: string

**Allowed values**: `organization.project`

### `name` (required)

The name of the project. This appears in reporting.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) of when the project was created.

**Type**: integer

### `archived_at`

The Unix timestamp (in seconds) of when the project was archived or `null`.

**Type**: integer

**Nullable**: Yes

### `status` (required)

`active` or `archived`

**Type**: string

**Allowed values**: `active`, `archived`

## Example

```json
{
    "id": "proj_abc",
    "object": "organization.project",
    "name": "Project example",
    "created_at": 1711471533,
    "archived_at": null,
    "status": "active"
}

```

