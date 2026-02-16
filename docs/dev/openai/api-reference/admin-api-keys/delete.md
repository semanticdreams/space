# Delete admin API key

`DELETE` `/organization/admin_api_keys/{key_id}`

Delete an organization admin API key

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `key_id` | string | Yes |  |

## Responses

### 200 - Confirmation that the API key was deleted.

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | No |  |  |  |
| `object` | string | No |  |  |  |
| `deleted` | boolean | No |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/organization/admin_api_keys/key_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
  "id": "key_abc",
  "object": "organization.admin_api_key.deleted",
  "deleted": true
}

```

