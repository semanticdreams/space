# Modify project user

`POST` `/organization/projects/{project_id}/users/{user_id}`

Modifies a user's role in the project.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |
| `user_id` | string | Yes | The ID of the user. |

## Request Body

The project user update request payload.

### Content Type: `application/json`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `role` | string | Yes |  | `owner`, `member` | `owner` or `member` |
## Responses

### 200 - Project user's role updated successfully.

#### Content Type: `application/json`

**Type**: object (6 properties)

Represents an individual user in a project.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.project.user` | The object type, which is always `organization.project.user` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the user |
| `email` | string | Yes |  |  | The email address of the user |
| `role` | string | Yes |  | `owner`, `member` | `owner` or `member` |
| `added_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the project was added. |
**Example:**

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

### 400 - Error response for various conditions.

#### Content Type: `application/json`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `error` | object (4 properties) | Yes |  |  |  |
|   ↳ `param` | string | Yes |  |  |  |
|   ↳ `type` | string | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X POST https://api.openai.com/v1/organization/projects/proj_abc/users/user_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
      "role": "owner"
  }'

```

### Response Example

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

