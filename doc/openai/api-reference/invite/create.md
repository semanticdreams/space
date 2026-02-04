# Create invite

`POST` `/organization/invites`

Create an invite for a user to the organization. The invite must be accepted by the user before they have access to the organization.

## Request Body

The invite request payload.

### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `email` | string | Yes |  |  | Send an email to this address |
| `role` | string | Yes |  | `reader`, `owner` | `owner` or `reader` |
| `projects` | array of object (2 properties) | No |  |  | An array of projects to which membership is granted at the same time the org invite is accepted. If omitted, the user will be invited to the default project for compatibility with legacy behavior. |


### Items in `projects` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | Project's public ID |
| `role` | string | Yes |  | `member`, `owner` | Project membership role |
## Responses

### 200 - User invited successfully.

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
curl -X POST https://api.openai.com/v1/organization/invites \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
      "email": "anotheruser@example.com",
      "role": "reader",
      "projects": [
        {
          "id": "project-xyz",
          "role": "member"
        },
        {
          "id": "project-abc",
          "role": "owner"
        }
      ]
  }'

```

### Response Example

```json
{
  "object": "organization.invite",
  "id": "invite-def",
  "email": "anotheruser@example.com",
  "role": "reader",
  "status": "pending",
  "invited_at": 1711471533,
  "expires_at": 1711471533,
  "accepted_at": null,
  "projects": [
    {
      "id": "project-xyz",
      "role": "member"
    },
    {
      "id": "project-abc",
      "role": "owner"
    }
  ]
}

```

