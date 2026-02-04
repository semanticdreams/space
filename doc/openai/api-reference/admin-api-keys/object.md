# The admin API key object

Represents an individual Admin API key in an org.

## Properties

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

## Property Details

### `object` (required)

The object type, which is always `organization.admin_api_key`

**Type**: string

### `id` (required)

The identifier, which can be referenced in API endpoints

**Type**: string

### `name` (required)

The name of the API key

**Type**: string

### `redacted_value` (required)

The redacted value of the API key

**Type**: string

### `value`

The value of the API key. Only shown on create.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) of when the API key was created

**Type**: integer

### `last_used_at` (required)

The Unix timestamp (in seconds) of when the API key was last used

**Type**: integer

**Nullable**: Yes

### `owner` (required)

**Type**: object (6 properties)

**Nested Properties**:

* `type`, `object`, `id`, `name`, `created_at`, `role`

## Example

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

