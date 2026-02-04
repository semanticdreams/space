# List organization certificates

`GET` `/organization/certificates`

List uploaded certificates for this organization.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `order` | string | No | Sort order by the `created_at` timestamp of the objects. `asc` for ascending order and `desc` for descending order. <br>  |

## Responses

### 200 - Certificates listed successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `data` | array of object (6 properties) | Yes |  |  |  |
| `first_id` | string | No |  |  |  |
| `last_id` | string | No |  |  |  |
| `has_more` | boolean | Yes |  |  |  |
| `object` | string | Yes |  | `list` |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `certificate`, `organization.certificate`, `organization.project.certificate` | The object type. <br>  <br> - If creating, updating, or getting a specific certificate, the object type is `certificate`. <br> - If listing, activating, or deactivating certificates for the organization, the object type is `organization.certificate`. <br> - If listing, activating, or deactivating certificates for a project, the object type is `organization.project.certificate`. <br>  |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the certificate. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the certificate was uploaded. |
| `certificate_details` | object (3 properties) | Yes |  |  |  |
|   ↳ `content` | string | No |  |  | The content of the certificate in PEM format. |
| `active` | boolean | No |  |  | Whether the certificate is currently active at the specified scope. Not returned when getting details for a specific certificate. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/certificates \
-H "Authorization: Bearer $OPENAI_ADMIN_KEY"

```

### Response Example

```json
{
  "object": "list",
  "data": [
    {
      "object": "organization.certificate",
      "id": "cert_abc",
      "name": "My Example Certificate",
      "active": true,
      "created_at": 1234567,
      "certificate_details": {
        "valid_at": 12345667,
        "expires_at": 12345678
      }
    },
  ],
  "first_id": "cert_abc",
  "last_id": "cert_abc",
  "has_more": false
}

```

