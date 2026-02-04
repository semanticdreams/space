# Delete an eval

`DELETE` `/evals/{eval_id}`

Delete an evaluation.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `eval_id` | string | Yes | The ID of the evaluation to delete. |

## Responses

### 200 - Successfully deleted the evaluation.

#### Content Type: `application/json`

**Type**: object (3 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `object` | string | Yes |  |  |  |
| `deleted` | boolean | Yes |  |  |  |
| `eval_id` | string | Yes |  |  |  |
### 404 - Evaluation not found.

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
curl https://api.openai.com/v1/evals/eval_abc123 \
  -X DELETE \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

### Response Example

```json
{
  "object": "eval.deleted",
  "deleted": true,
  "eval_id": "eval_abc123"
}

```

