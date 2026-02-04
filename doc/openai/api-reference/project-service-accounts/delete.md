# Delete project service account

`DELETE` `/organization/projects/{project_id}/service_accounts/{service_account_id}`

Deletes a service account from the project.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |
| `service_account_id` | string | Yes | The ID of the service account. |

## Responses

### 200 - Project service account deleted successfully.

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.project.service_account.deleted` |  |
| `id` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X DELETE https://api.openai.com/v1/organization/projects/proj_abc/service_accounts/svc_acct_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "organization.project.service_account.deleted",
    "id": "svc_acct_abc",
    "deleted": true
}

```

