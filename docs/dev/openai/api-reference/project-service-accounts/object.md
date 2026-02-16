# The project service account object

Represents an individual service account in a project.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.project.service_account` | The object type, which is always `organization.project.service_account` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the service account |
| `role` | string | Yes |  | `owner`, `member` | `owner` or `member` |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the service account was created |

## Property Details

### `object` (required)

The object type, which is always `organization.project.service_account`

**Type**: string

**Allowed values**: `organization.project.service_account`

### `id` (required)

The identifier, which can be referenced in API endpoints

**Type**: string

### `name` (required)

The name of the service account

**Type**: string

### `role` (required)

`owner` or `member`

**Type**: string

**Allowed values**: `owner`, `member`

### `created_at` (required)

The Unix timestamp (in seconds) of when the service account was created

**Type**: integer

## Example

```json
{
    "object": "organization.project.service_account",
    "id": "svc_acct_abc",
    "name": "Service Account",
    "role": "owner",
    "created_at": 1711471533
}

```

