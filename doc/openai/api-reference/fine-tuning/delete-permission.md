# Delete checkpoint permission

`DELETE` `/fine_tuning/checkpoints/{fine_tuned_model_checkpoint}/permissions/{permission_id}`

**NOTE:** This endpoint requires an [admin API key](../admin-api-keys).

Organization owners can use this endpoint to delete a permission for a fine-tuned model checkpoint.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `fine_tuned_model_checkpoint` | string | Yes | The ID of the fine-tuned model checkpoint to delete a permission for. <br>  |
| `permission_id` | string | Yes | The ID of the fine-tuned model checkpoint permission to delete. <br>  |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The ID of the fine-tuned model checkpoint permission that was deleted. |
| `object` | string | Yes |  | `checkpoint.permission` | The object type, which is always "checkpoint.permission". |
| `deleted` | boolean | Yes |  |  | Whether the fine-tuned model checkpoint permission was successfully deleted. |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/fine_tuning/checkpoints/ft:gpt-4o-mini-2024-07-18:org:weather:B7R9VjQd/permissions/cp_zc4Q7MP6XxulcVzj4MZdwsAB \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

### Response Example

```json
{
  "object": "checkpoint.permission",
  "id": "cp_zc4Q7MP6XxulcVzj4MZdwsAB",
  "deleted": true
}

```

