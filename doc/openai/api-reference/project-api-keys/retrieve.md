# Retrieve project API key

`GET` `/organization/projects/{project_id}/api_keys/{key_id}`

Retrieves an API key in the project.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |
| `key_id` | string | Yes | The ID of the API key. |

## Responses

### 200 - Project API key retrieved successfully.

#### Content Type: `application/json`

**Type**: object (7 properties)

Represents an individual API key in a project.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.project.api_key` | The object type, which is always `organization.project.api_key` |
| `redacted_value` | string | Yes |  |  | The redacted value of the API key |
| `name` | string | Yes |  |  | The name of the API key |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the API key was created |
| `last_used_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the API key was last used. |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `owner` | object (3 properties) | Yes |  |  |  |
|     ↳ `name` | string | Yes |  |  | The name of the user |
|     ↳ `email` | string | Yes |  |  | The email address of the user |
|     ↳ `role` | string | Yes |  | `owner`, `member` | `owner` or `member` |
|     ↳ `added_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the project was added. |
|   ↳ `service_account` | object (5 properties) | No |  |  | Represents an individual service account in a project. |
|     ↳ `name` | string | Yes |  |  | The name of the service account |
|     ↳ `role` | string | Yes |  | `owner`, `member` | `owner` or `member` |
|     ↳ `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the service account was created |
**Example:**

```json
{
    "object": "organization.project.api_key",
    "redacted_value": "sk-abc...def",
    "name": "My API Key",
    "created_at": 1711471533,
    "last_used_at": 1711471534,
    "id": "key_abc",
    "owner": {
        "type": "user",
        "user": {
            "object": "organization.project.user",
            "id": "user_abc",
            "name": "First Last",
            "email": "user@example.com",
            "role": "owner",
            "created_at": 1711471533
        }
    }
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/projects/proj_abc/api_keys/key_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "organization.project.api_key",
    "redacted_value": "sk-abc...def",
    "name": "My API Key",
    "created_at": 1711471533,
    "last_used_at": 1711471534,
    "id": "key_abc",
    "owner": {
        "type": "user",
        "user": {
            "object": "organization.project.user",
            "id": "user_abc",
            "name": "First Last",
            "email": "user@example.com",
            "role": "owner",
            "added_at": 1711471533
        }
    }
}

```

