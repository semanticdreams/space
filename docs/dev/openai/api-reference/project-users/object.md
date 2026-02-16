# The project user object

Represents an individual user in a project.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.project.user` | The object type, which is always `organization.project.user` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the user |
| `email` | string | Yes |  |  | The email address of the user |
| `role` | string | Yes |  | `owner`, `member` | `owner` or `member` |
| `added_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the project was added. |

## Property Details

### `object` (required)

The object type, which is always `organization.project.user`

**Type**: string

**Allowed values**: `organization.project.user`

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

`owner` or `member`

**Type**: string

**Allowed values**: `owner`, `member`

### `added_at` (required)

The Unix timestamp (in seconds) of when the project was added.

**Type**: integer

## Example

```json
{
    "object": "organization.project.user",
    "id": "user_abc",
    "name": "First Last",
    "email": "user@example.com",
    "role": "owner",
    "added_at": 1711471533
}

```

