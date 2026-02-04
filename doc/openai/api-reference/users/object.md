# The user object

Represents an individual `user` within an organization.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.user` | The object type, which is always `organization.user` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the user |
| `email` | string | Yes |  |  | The email address of the user |
| `role` | string | Yes |  | `owner`, `reader` | `owner` or `reader` |
| `added_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the user was added. |

## Property Details

### `object` (required)

The object type, which is always `organization.user`

**Type**: string

**Allowed values**: `organization.user`

### `id` (required)

The identifier, which can be referenced in API endpoints

**Type**: string

### `name` (required)

The name of the user

**Type**: string

### `email` (required)

The email address of the user

**Type**: string

### `role` (required)

`owner` or `reader`

**Type**: string

**Allowed values**: `owner`, `reader`

### `added_at` (required)

The Unix timestamp (in seconds) of when the user was added.

**Type**: integer

## Example

```json
{
    "object": "organization.user",
    "id": "user_abc",
    "name": "First Last",
    "email": "user@example.com",
    "role": "owner",
    "added_at": 1711471533
}

```

