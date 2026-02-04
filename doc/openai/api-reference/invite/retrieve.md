# Retrieve invite

`GET` `/organization/invites/{invite_id}`

Retrieves an invite.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `invite_id` | string | Yes | The ID of the invite to retrieve. |

## Responses

### 200 - Invite retrieved successfully.

#### Content Type: `application/json`

**Type**: object (9 properties)

Represents an individual `invite` to the organization.

#### Properties:

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
**Example:**

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

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/invites/invite-abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "organization.invite",
    "id": "invite-abc",
    "email": "user@example.com",
    "role": "owner",
    "status": "accepted",
    "invited_at": 1711471533,
    "expires_at": 1711471533,
    "accepted_at": 1711471533
}

```

