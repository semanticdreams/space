# Retrieve project

`GET` `/organization/projects/{project_id}`

Retrieves a project.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |

## Responses

### 200 - Project retrieved successfully.

#### Content Type: `application/json`

**Type**: object (6 properties)

Represents an individual project.

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `object` | string | Yes |  | `organization.project` | The object type, which is always `organization.project` |
| `name` | string | Yes |  |  | The name of the project. This appears in reporting. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the project was created. |
| `archived_at` | integer | No |  |  | The Unix timestamp (in seconds) of when the project was archived or `null`. |
| `status` | string | Yes |  | `active`, `archived` | `active` or `archived` |
**Example:**

```json
{
    "id": "proj_abc",
    "object": "organization.project",
    "name": "Project example",
    "created_at": 1711471533,
    "archived_at": null,
    "status": "active"
}

```

## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/projects/proj_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "id": "proj_abc",
    "object": "organization.project",
    "name": "Project example",
    "created_at": 1711471533,
    "archived_at": null,
    "status": "active"
}

```

