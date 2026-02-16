# The certificate object

Represents an individual `certificate` uploaded to the organization.

## Properties

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `certificate`, `organization.certificate`, `organization.project.certificate` | The object type. <br>  <br> - If creating, updating, or getting a specific certificate, the object type is `certificate`. <br> - If listing, activating, or deactivating certificates for the organization, the object type is `organization.certificate`. <br> - If listing, activating, or deactivating certificates for a project, the object type is `organization.project.certificate`. <br>  |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the certificate. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the certificate was uploaded. |
| `certificate_details` | object (3 properties) | Yes |  |  |  |
|   ↳ `content` | string | No |  |  | The content of the certificate in PEM format. |
| `active` | boolean | No |  |  | Whether the certificate is currently active at the specified scope. Not returned when getting details for a specific certificate. |

## Property Details

### `object` (required)

The object type.

- If creating, updating, or getting a specific certificate, the object type is `certificate`.
- If listing, activating, or deactivating certificates for the organization, the object type is `organization.certificate`.
- If listing, activating, or deactivating certificates for a project, the object type is `organization.project.certificate`.


**Type**: string

**Allowed values**: `certificate`, `organization.certificate`, `organization.project.certificate`

### `id` (required)

The identifier, which can be referenced in API endpoints

**Type**: string

### `name` (required)

The name of the certificate.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) of when the certificate was uploaded.

**Type**: integer

### `certificate_details` (required)

**Type**: object (3 properties)

**Nested Properties**:

* `valid_at`, `expires_at`, `content`

### `active`

Whether the certificate is currently active at the specified scope. Not returned when getting details for a specific certificate.

**Type**: boolean

## Example

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

