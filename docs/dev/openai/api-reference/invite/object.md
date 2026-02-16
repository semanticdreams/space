# The invite object

Represents an individual `invite` to the organization.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.invite` | The object type, which is always `organization.invite` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `email` | string | Yes |  |  | The email address of the individual to whom the invite was sent |
| `role` | string | Yes |  | `owner`, `reader` | `owner` or `reader` |
| `status` | string | Yes |  | `accepted`, `expired`, `pending` | `accepted`,`expired`, or `pending` |
| `invited_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the invite was sent. |
| `expires_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the invite expires. |
| `accepted_at` | integer | No |  |  | The Unix timestamp (in seconds) of when the invite was accepted. |
| `projects` | array of object (2 properties) | No |  |  | The projects that were granted membership upon acceptance of the invite. |


### Items in `projects` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  | Project's public ID |
| `role` | string | No |  | `member`, `owner` | Project membership role |

## Property Details

### `object` (required)

The object type, which is always `organization.invite`

**Type**: string

**Allowed values**: `organization.invite`

### `id` (required)

The identifier, which can be referenced in API endpoints

**Type**: string

### `email` (required)

The email address of the individual to whom the invite was sent

**Type**: string

### `role` (required)

`owner` or `reader`

**Type**: string

**Allowed values**: `owner`, `reader`

### `status` (required)

`accepted`,`expired`, or `pending`

**Type**: string

**Allowed values**: `accepted`, `expired`, `pending`

### `invited_at` (required)

The Unix timestamp (in seconds) of when the invite was sent.

**Type**: integer

### `expires_at` (required)

The Unix timestamp (in seconds) of when the invite expires.

**Type**: integer

### `accepted_at`

The Unix timestamp (in seconds) of when the invite was accepted.

**Type**: integer

### `projects`

The projects that were granted membership upon acceptance of the invite.

**Type**: array of object (2 properties)

## Example

```json
{
  "object": "organization.invite",
  "id": "invite-abc",
  "email": "user@example.com",
  "role": "owner",
  "status": "accepted",
  "invited_at": 1711471533,
  "expires_at": 1711471533,
  "accepted_at": 1711471533,
  "projects": [
    {
      "id": "project-xyz",
      "role": "member"
    }
  ]
}

```

