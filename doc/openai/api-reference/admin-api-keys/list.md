# List all organization and project API keys.

`GET` `/organization/admin_api_keys`

List organization API keys

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No |  |
| `order` | string | No |  |
| `limit` | integer | No |  |

## Responses

### 200 - A list of organization API keys.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | No |  |  |  |
| `data` | array of object (8 properties) | No |  |  |  |
| `has_more` | boolean | No |  |  |  |
| `first_id` | string | No |  |  |  |
| `last_id` | string | No |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  |  | The object type, which is always `organization.admin_api_key` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the API key |
| `redacted_value` | string | Yes |  |  | The redacted value of the API key |
| `value` | string | No |  |  | The value of the API key. Only shown on create. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the API key was created |
| `last_used_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the API key was last used |
| `owner` | object (6 properties) | Yes |  |  |  |
|   ↳ `id` | string | No |  |  | The identifier, which can be referenced in API endpoints |
|   ↳ `name` | string | No |  |  | The name of the user |
|   ↳ `created_at` | integer | No |  |  | The Unix timestamp (in seconds) of when the user was created |
|   ↳ `role` | string | No |  |  | Always `owner` |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/admin_api_keys?after=key_abc&limit=20 \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "object": "organization.admin_api_key",
      "id": "key_abc",
      "name": "Main Admin Key",
      "redacted_value": "sk-admin...def",
      "created_at": 1711471533,
      "last_used_at": 1711471534,
      "owner": {
        "type": "service_account",
        "object": "organization.service_account",
        "id": "sa_456",
        "name": "My Service Account",
        "created_at": 1711471533,
        "role": "member"
      }
    }
  ],
  "first_id": "key_abc",
  "last_id": "key_abc",
  "has_more": false
}

```

