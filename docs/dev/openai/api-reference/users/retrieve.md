# Retrieve user

`GET` `/organization/users/{user_id}`

Retrieves a user by their identifier.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `user_id` | string | Yes | The ID of the user. |

## Responses

### 200 - User retrieved successfully.

#### Content Type: `application/json`

**Type**: object (6 properties)

Represents an individual `user` within an organization.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.user` | The object type, which is always `organization.user` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the user |
| `email` | string | Yes |  |  | The email address of the user |
| `role` | string | Yes |  | `owner`, `reader` | `owner` or `reader` |
| `added_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the user was added. |
**Example:**

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

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/users/user_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

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

