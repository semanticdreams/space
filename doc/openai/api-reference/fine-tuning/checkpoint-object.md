# The fine-tuning job checkpoint object

The `fine_tuning.job.checkpoint` object represents a model checkpoint for a fine-tuning job that is ready to use.


## Properties

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

## Property Details

### `id` (required)

The checkpoint identifier, which can be referenced in the API endpoints.

**Type**: string

### `created_at` (required)

The Unix timestamp (in seconds) for when the checkpoint was created.

**Type**: integer

### `fine_tuned_model_checkpoint` (required)

The name of the fine-tuned checkpoint model that is created.

**Type**: string

### `step_number` (required)

The step number that the checkpoint was created at.

**Type**: integer

### `metrics` (required)

Metrics at the step number during the fine-tuning job.

**Type**: object (7 properties)

**Nested Properties**:

* `step`, `train_loss`, `train_mean_token_accuracy`, `valid_loss`, `valid_mean_token_accuracy`, `full_valid_loss`, `full_valid_mean_token_accuracy`

### `fine_tuning_job_id` (required)

The name of the fine-tuning job that this checkpoint was created from.

**Type**: string

### `object` (required)

The object type, which is always "fine_tuning.job.checkpoint".

**Type**: string

**Allowed values**: `fine_tuning.job.checkpoint`

## Example

```json
{
  "object": "fine_tuning.job.checkpoint",
  "id": "ftckpt_qtZ5Gyk4BLq1SfLFWp3RtO3P",
  "created_at": 1712211699,
  "fine_tuned_model_checkpoint": "ft:gpt-4o-mini-2024-07-18:my-org:custom_suffix:9ABel2dg:ckpt-step-88",
  "fine_tuning_job_id": "ftjob-fpbNQ3H1GrMehXRf8cO97xTN",
  "metrics": {
    "step": 88,
    "train_loss": 0.478,
    "train_mean_token_accuracy": 0.924,
    "valid_loss": 10.112,
    "valid_mean_token_accuracy": 0.145,
    "full_valid_loss": 0.567,
    "full_valid_mean_token_accuracy": 0.944
  },
  "step_number": 88
}

```

