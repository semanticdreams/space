# Get certificate

`GET` `/organization/certificates/{certificate_id}`

Get a certificate that has been uploaded to the organization.

You can get a certificate regardless of whether it is active or not.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `cert_id` | string | Yes | Unique ID of the certificate to retrieve. |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `include` | array of string | No | A list of additional fields to include in the response. Currently the only supported value is `content` to fetch the PEM content of the certificate. |

## Responses

### 200 - Certificate retrieved successfully.

#### Content Type: `application/json`

**Type**: object (6 properties)

Represents an individual `certificate` uploaded to the organization.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `certificate`, `organization.certificate`, `organization.project.certificate` | The object type. <br>  <br> - If creating, updating, or getting a specific certificate, the object type is `certificate`. <br> - If listing, activating, or deactivating certificates for the organization, the object type is `organization.certificate`. <br> - If listing, activating, or deactivating certificates for a project, the object type is `organization.project.certificate`. <br>  |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the certificate. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the certificate was uploaded. |
| `certificate_details` | object (3 properties) | Yes |  |  |  |
|   ↳ `content` | string | No |  |  | The content of the certificate in PEM format. |
| `active` | boolean | No |  |  | Whether the certificate is currently active at the specified scope. Not returned when getting details for a specific certificate. |
**Example:**

```json
{
  "object": "certificate",
  "id": "cert_abc",
  "name": "My Certificate",
  "created_at": 1234567,
  "certificate_details": {
    "valid_at": 1234567,
    "expires_at": 12345678,
    "content": "-----BEGIN CERTIFICATE----- MIIGAjCCA...6znFlOW+ -----END CERTIFICATE-----"
  }
}

```

## Examples

### Request Examples

#### curl
```bash
curl "https://api.openai.com/v1/organization/certificates/cert_abc?include[]=content" \
-H "Authorization: Bearer $OPENAI_ADMIN_KEY"

```

### Response Example

```json
{
  "object": "certificate",
  "id": "cert_abc",
  "name": "My Example Certificate",
  "created_at": 1234567,
  "certificate_details": {
    "valid_at": 1234567,
    "expires_at": 12345678,
    "content": "-----BEGIN CERTIFICATE-----MIIDeT...-----END CERTIFICATE-----"
  }
}

```

