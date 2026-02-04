# Retrieve project service account

`GET` `/organization/projects/{project_id}/service_accounts/{service_account_id}`

Retrieves a service account in the project.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |
| `service_account_id` | string | Yes | The ID of the service account. |

## Responses

### 200 - Project service account retrieved successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

Represents an individual service account in a project.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `organization.project.service_account` | The object type, which is always `organization.project.service_account` |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `name` | string | Yes |  |  | The name of the service account |
| `role` | string | Yes |  | `owner`, `member` | `owner` or `member` |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the service account was created |
**Example:**

```json
{
    "object": "organization.project.service_account",
    "id": "svc_acct_abc",
    "name": "Service Account",
    "role": "owner",
    "created_at": 1711471533
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/projects/proj_abc/service_accounts/svc_acct_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "organization.project.service_account",
    "id": "svc_acct_abc",
    "name": "Service Account",
    "role": "owner",
    "created_at": 1711471533
}

```

