# List projects

`GET` `/organization/projects`

Returns a list of projects.

## Parameters

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `limit` | integer | No | A limit on the number of objects to be returned. Limit can range between 1 and 100, and the default is 20. <br>  |
| `after` | string | No | A cursor for use in pagination. `after` is an object ID that defines your place in the list. For instance, if you make a list request and receive 100 objects, ending with obj_foo, your subsequent call can include after=obj_foo in order to fetch the next page of the list. <br>  |
| `include_archived` | boolean | No | If `true` returns all projects including those that have been `archived`. Archived projects are not included by default. |

## Responses

### 200 - Projects listed successfully.

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  | `list` |  |
| `data` | array of object (6 properties) | Yes |  |  |  |
| `first_id` | string | Yes |  |  |  |
| `last_id` | string | Yes |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The identifier, which can be referenced in API endpoints |
| `object` | string | Yes |  | `organization.project` | The object type, which is always `organization.project` |
| `name` | string | Yes |  |  | The name of the project. This appears in reporting. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) of when the project was created. |
| `archived_at` | integer | No |  |  | The Unix timestamp (in seconds) of when the project was archived or `null`. |
| `status` | string | Yes |  | `active`, `archived` | `active` or `archived` |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/organization/projects?after=proj_abc&limit=20&include_archived=false \
  -H "Authorization: Bearer $OPENAI_ADMIN_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
    "object": "list",
    "data": [
        {
            "id": "proj_abc",
            "object": "organization.project",
            "name": "Project example",
            "created_at": 1711471533,
            "archived_at": null,
            "status": "active"
        }
    ],
    "first_id": "proj-abc",
    "last_id": "proj-xyz",
    "has_more": false
}

```

