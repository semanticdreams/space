# Delete certificate

`DELETE` `/organization/certificates/{certificate_id}`

Delete a certificate from the organization.

The certificate must be inactive for the organization and all projects.


## Responses

### 200 - Certificate deleted successfully.

#### Content Type: `application/json`

**Type**: object (2 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `certificate.deleted` | The object type, must be `certificate.deleted`. |
| `id` | string | Yes |  |  | The ID of the certificate that was deleted. |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/organization/certificates/cert_abc \
-H "Authorization: Bearer $OPENAI_ADMIN_KEY"

```

### Response Example

```json
{
  "object": "certificate.deleted",
  "id": "cert_abc"
}

```

