# List invites

`GET` `/organization/invites`

Returns a list of invites in the organization.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |

## Responses

### 200 - Invites listed successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` | The object type, which is always `list` |
| `data` | array of object (9 properties) | Yes |  |  |  |
| `first_id` | string | No |  |  | The first `invite_id` in the retrieved `list` |
| `last_id` | string | No |  |  | The last `invite_id` in the retrieved `list` |
| `has_more` | boolean | No |  |  | The `has_more` property is used for pagination to indicate there are additional results. |


### Items in `data` array

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
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/invites?after=invite-abc&limit=20 \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
  "object": "list",
  "data": [
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
  ],
  "first_id": "invite-abc",
  "last_id": "invite-abc",
  "has_more": false
}

```

