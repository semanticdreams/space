# Delete invite

`DELETE` `/organization/invites/{invite_id}`

Delete an invite. If the invite has already been accepted, it cannot be deleted.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `invite_id` | string | Yes | The ID of the invite to delete. |

## Responses

### 200 - Invite deleted successfully.

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.invite.deleted` | The object type, which is always `organization.invite.deleted` |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/organization/invites/invite-abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "organization.invite.deleted",
    "id": "invite-abc",
    "deleted": true
}

```

