# Modify project

`POST` `/organization/projects/{project_id}`

Modifies a project in the organization.

## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `project_id` | string | Yes | The ID of the project. |

## Request Body

The project update request payload.

### Content Type: `application/json`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `name` | string | Yes |  |  | The updated name of the project, this name appears in reports. |
## Responses

### 200 - Project updated successfully.

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

### 400 - Error response when updating the default project.

#### Content Type: `application/json`

**Type**: object (1 property)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `error` | object (4 properties) | Yes |  |  |  |
|   ↳ `param` | string | Yes |  |  |  |
|   ↳ `type` | string | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl -X POST https://api.openai.com/v1/organization/projects/proj_abc \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
      "name": "Project DEF"
  }'

```

