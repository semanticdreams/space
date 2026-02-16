# Delete eval run

`DELETE` `/evals/{eval_id}/runs/{run_id}`

Delete an eval run.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `eval_id` | string | Yes | The ID of the evaluation to delete the run from. |
| `run_id` | string | Yes | The ID of the run to delete. |

## Responses

### 200 - Successfully deleted the eval run

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | No |  |  |  |
| `deleted` | boolean | No |  |  |  |
| `run_id` | string | No |  |  |  |
### 404 - Run not found

#### Content Type: `application/json`

**Type**: object (4 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `code` | string | Yes |  |  |  |
| `message` | string | Yes |  |  |  |
| `param` | string | Yes |  |  |  |
| `type` | string | Yes |  |  |  |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/evals/eval_123abc/runs/evalrun_abc456 \
  -X DELETE \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json"

```

### Response Example

```json
{
  "object": "eval.run.deleted",
  "deleted": true,
  "run_id": "evalrun_abc456"
}

```

