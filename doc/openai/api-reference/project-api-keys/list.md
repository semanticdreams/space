# List project API keys

`GET` `/organization/projects/{project_id}/api_keys`

Returns a list of API keys in the project.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |

## Responses

### 200 - Project API keys listed successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` |  |
| `data` | array of object (7 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

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
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/projects/proj_abc/api_keys?after=key_abc&limit=20 \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "list",
    "data": [
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
    ],
    "first_id": "key_abc",
    "last_id": "key_xyz",
    "has_more": false
}

```

