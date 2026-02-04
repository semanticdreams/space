# Delete user

`DELETE` `/organization/users/{user_id}`

Deletes a user from the organization.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `user_id` | string | Yes | The ID of the user. |

## Responses

### 200 - User deleted successfully.

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.user.deleted` |  |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/organization/users/user_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "organization.user.deleted",
    "id": "user_abc",
    "deleted": true
}

```

