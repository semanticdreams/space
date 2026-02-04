# List fine-tuning checkpoints

`GET` `/fine_tuning/jobs/{fine_tuning_job_id}/checkpoints`

List checkpoints for a fine-tuning job.


## Parameters

### Path Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `fine_tuning_job_id` | string | Yes | The ID of the fine-tuning job to get checkpoints for. <br>  |

### Query Parameters

| Name | Type | Required | Description |
| ---- | ---- | -------- | ----------- |
| `after` | string | No | Identifier for the last checkpoint ID from the previous pagination request. |
| `limit` | integer | No | Number of checkpoints to retrieve. |

## Responses

### 200 - OK

#### Content Type: `application/json`

**Type**: object (5 properties)

#### Properties:

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `data` | array of object (7 properties) | Yes |  |  |  |
| `object` | string | Yes |  | `list` |  |
| `first_id` | string | No |  |  |  |
| `last_id` | string | No |  |  |  |
| `has_more` | boolean | Yes |  |  |  |


### Items in `data` array

| Property | Type | Required | Default | Allowed Values | Description |
| -------- | ---- | -------- | ------- | -------------- | ----------- |
| `id` | string | Yes |  |  | The checkpoint identifier, which can be referenced in the API endpoints. |
| `created_at` | integer | Yes |  |  | The Unix timestamp (in seconds) for when the checkpoint was created. |
| `fine_tuned_model_checkpoint` | string | Yes |  |  | The name of the fine-tuned checkpoint model that is created. |
| `step_number` | integer | Yes |  |  | The step number that the checkpoint was created at. |
| `metrics` | object (7 properties) | Yes |  |  | Metrics at the step number during the fine-tuning job. |
|   ↳ `train_mean_token_accuracy` | number | No |  |  |  |
|   ↳ `valid_loss` | number | No |  |  |  |
|   ↳ `valid_mean_token_accuracy` | number | No |  |  |  |
|   ↳ `full_valid_loss` | number | No |  |  |  |
|   ↳ `full_valid_mean_token_accuracy` | number | No |  |  |  |
| `fine_tuning_job_id` | string | Yes |  |  | The name of the fine-tuning job that this checkpoint was created from. |
| `object` | string | Yes |  | `fine_tuning.job.checkpoint` | The object type, which is always "fine_tuning.job.checkpoint". |
## Examples

### Request Examples

#### curl
```bash
curl https://api.openai.com/v1/fine_tuning/jobs/ftjob-abc123/checkpoints \
  -H "Authorization: Bearer $OPENAI_API_KEY"

```

### Response Example

```json
{
  "object": "list"
  "data": [
    {
      "object": "fine_tuning.job.checkpoint",
      "id": "ftckpt_zc4Q7MP6XxulcVzj4MZdwsAB",
      "created_at": 1721764867,
      "fine_tuned_model_checkpoint": "ft:gpt-4o-mini-2024-07-18:my-org:custom-suffix:96olL566:ckpt-step-2000",
      "metrics": {
        "full_valid_loss": 0.134,
        "full_valid_mean_token_accuracy": 0.874
      },
      "fine_tuning_job_id": "ftjob-abc123",
      "step_number": 2000,
    },
    {
      "object": "fine_tuning.job.checkpoint",
      "id": "ftckpt_enQCFmOTGj3syEpYVhBRLTSy",
      "created_at": 1721764800,
      "fine_tuned_model_checkpoint": "ft:gpt-4o-mini-2024-07-18:my-org:custom-suffix:7q8mpxmy:ckpt-step-1000",
      "metrics": {
        "full_valid_loss": 0.167,
        "full_valid_mean_token_accuracy": 0.781
      },
      "fine_tuning_job_id": "ftjob-abc123",
      "step_number": 1000,
    },
  ],
  "first_id": "ftckpt_zc4Q7MP6XxulcVzj4MZdwsAB",
  "last_id": "ftckpt_enQCFmOTGj3syEpYVhBRLTSy",
  "has_more": true
}

```

