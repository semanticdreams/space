# Create admin API key

`POST` `/organization/admin_api_keys`

Create an organization admin API key

## Request Body

### Content Type: `application/json`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `name` | string | Yes |  |  |  |
## Responses

### 200 - The newly created admin API key.

#### Content Type: `application/json`

**Type**: object (8 properties)

Represents an individual Admin API key in an org.

#### Properties:

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
**Example:**

```json
{
  "object": "organization.admin_api_key",
  "id": "key_abc",
  "name": "Main Admin Key",
  "redacted_value": "sk-admin...xyz",
  "created_at": 1711471533,
  "last_used_at": 1711471534,
  "owner": {
    "type": "user",
    "object": "organization.user",
    "id": "user_123",
    "name": "John Doe",
    "created_at": 1711471533,
    "role": "owner"
  }
}

```

## Examples

### Request Examples

#### curl
```bash
curl -X POST https://api.openai.com/v1/organization/admin_api_keys \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
      "name": "New Admin Key"
  }'

```

### Response Example

```json
{
  "object": "organization.admin_api_key",
  "id": "key_xyz",
  "name": "New Admin Key",
  "redacted_value": "sk-admin...xyz",
  "created_at": 1711471533,
  "last_used_at": 1711471534,
  "owner": {
    "type": "user",
    "object": "organization.user",
    "id": "user_123",
    "name": "John Doe",
    "created_at": 1711471533,
    "role": "owner"
  },
  "value": "sk-admin-1234abcd"
}

```

